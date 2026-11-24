-- =====================================================================
-- DermaScreen: PostgreSQL security setup
-- Based on ADMS Lesson 7 - PostgreSQL Security for Integrated Web Systems
--
-- Run AFTER dermascreen_schema.sql, as a superuser (e.g. postgres).
-- Passwords are passed in, never written in this file (slide 18):
--
--   psql -d dermascreen \
--        -v app_pw='<strong password 1>' \
--        -v report_pw='<strong password 2>' \
--        -v admin_pw='<strong password 3>' \
--        -f dermascreen_security.sql
--
-- Needs PostgreSQL 15 or newer (security_invoker views).
-- Safe to run more than once.
--
-- Think of it as the slides do:  Who can connect?  What can they do?
-- Which rows can they see?
-- =====================================================================

\set ON_ERROR_STOP on

\if :{?app_pw}
\else
  \echo 'Missing -v app_pw=...  (see the top of this file)'
  \quit
\endif
\if :{?report_pw}
\else
  \echo 'Missing -v report_pw=...  (see the top of this file)'
  \quit
\endif
\if :{?admin_pw}
\else
  \echo 'Missing -v admin_pw=...  (see the top of this file)'
  \quit
\endif

SET password_encryption = 'scram-sha-256';

-- ---------------------------------------------------------------------
-- STEP 1-3. Roles (slides 5, 6, 10, 11)
--
--   db_admin        LOGIN    developer / migrations / first admin account
--   app_service     LOGIN    the FastAPI backend (the ONLY app connection)
--   report_reader   LOGIN    reports page, aggregated numbers only
--   app_rw_group    NOLOGIN  group role: privileges of the backend
--   report_ro_group NOLOGIN  group role: privileges of the reports page
--
-- None of them is a superuser, can create databases or roles, or bypasses
-- row-level security.
-- ---------------------------------------------------------------------
SELECT 'CREATE ROLE db_admin LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'db_admin') \gexec
SELECT 'CREATE ROLE app_service LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_service') \gexec
SELECT 'CREATE ROLE report_reader LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'report_reader') \gexec
SELECT 'CREATE ROLE app_rw_group NOLOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_rw_group') \gexec
SELECT 'CREATE ROLE report_ro_group NOLOGIN'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'report_ro_group') \gexec

SELECT format('ALTER ROLE db_admin PASSWORD %L', :'admin_pw') \gexec
SELECT format('ALTER ROLE app_service PASSWORD %L', :'app_pw') \gexec
SELECT format('ALTER ROLE report_reader PASSWORD %L', :'report_pw') \gexec

-- Role membership (slide 10): permissions go to the group, users join it.
GRANT app_rw_group    TO app_service;
GRANT report_ro_group TO report_reader;

-- Convenience + safety limits for the login roles
ALTER ROLE app_service   SET search_path = skin_classification_schema;
ALTER ROLE report_reader SET search_path = skin_classification_schema;
ALTER ROLE db_admin      SET search_path = skin_classification_schema, public;
ALTER ROLE app_service   SET statement_timeout = '30s';
ALTER ROLE report_reader SET statement_timeout = '15s';
ALTER ROLE app_service   CONNECTION LIMIT 50;
ALTER ROLE report_reader CONNECTION LIMIT 5;

-- ---------------------------------------------------------------------
-- STEP 4. Start from NO access (slide 8: "start with no access, then add")
-- Only these roles may connect to this database at all.
-- ---------------------------------------------------------------------
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database()) \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO db_admin, app_service, report_reader',
              current_database()) \gexec

-- Nobody can create objects in the default schema (slide 9)
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Ownership: db_admin owns the schema and every object in it, so the
-- backend account owns nothing and can never DROP or ALTER anything.
-- (Table owners bypass RLS, which is why the backend must not own tables.)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    r record;
    sch constant text := 'skin_classification_schema';
BEGIN
    EXECUTE format('ALTER SCHEMA %I OWNER TO db_admin', sch);

    FOR r IN SELECT c.relname, c.relkind
             FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = sch AND c.relkind IN ('r', 'v')   -- identity sequences follow their table
    LOOP
        EXECUTE format('ALTER %s %I.%I OWNER TO db_admin',
                       CASE r.relkind WHEN 'v' THEN 'VIEW' ELSE 'TABLE' END, sch, r.relname);
    END LOOP;

    FOR r IN SELECT p.oid::regprocedure AS sig
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = sch
    LOOP
        EXECUTE format('ALTER FUNCTION %s OWNER TO db_admin', r.sig);
    END LOOP;

    FOR r IN SELECT t.typname
             FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
             WHERE n.nspname = sch AND t.typtype = 'e'
    LOOP
        EXECUTE format('ALTER TYPE %I.%I OWNER TO db_admin', sch, r.typname);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Application context helpers (slides 12-14)
--
-- The backend tells PostgreSQL who is calling, once per transaction:
--     SELECT set_config('app.current_user_id', '7', true);
--     SELECT set_config('app.current_role', 'patient', true);
-- Valid app.current_role values:
--     patient | medical_reviewer | administrator | auth
-- ('auth' = the login / register / refresh-token code path, which has to
--  look up an account BEFORE it knows who the user is.)
--
-- If nothing is set, these return NULL and every row policy denies access.
-- ---------------------------------------------------------------------
SET ROLE db_admin;

CREATE OR REPLACE FUNCTION skin_classification_schema.app_user_id()
RETURNS bigint LANGUAGE sql STABLE AS
$$ SELECT NULLIF(current_setting('app.current_user_id', true), '')::bigint $$;

CREATE OR REPLACE FUNCTION skin_classification_schema.app_role()
RETURNS text LANGUAGE sql STABLE AS
$$ SELECT NULLIF(current_setting('app.current_role', true), '') $$;

REVOKE ALL ON FUNCTION skin_classification_schema.app_user_id() FROM PUBLIC;
REVOKE ALL ON FUNCTION skin_classification_schema.app_role()    FROM PUBLIC;
GRANT EXECUTE ON FUNCTION skin_classification_schema.app_user_id() TO app_rw_group, report_ro_group;
GRANT EXECUTE ON FUNCTION skin_classification_schema.app_role()    TO app_rw_group, report_ro_group;

-- A patient may edit their own profile row, but must NOT be able to promote
-- themselves to administrator, unlock their own account, or reactivate
-- themselves. RLS works on rows, not columns, so a trigger guards these.
CREATE OR REPLACE FUNCTION skin_classification_schema.protect_user_columns()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    -- only applies to the backend; db_admin maintenance is not restricted
    IF pg_has_role(current_user, 'app_rw_group', 'member')
       AND skin_classification_schema.app_role() IS DISTINCT FROM 'administrator' THEN

        IF NEW.role IS DISTINCT FROM OLD.role
           OR NEW.is_active IS DISTINCT FROM OLD.is_active THEN
            RAISE EXCEPTION 'only an administrator may change role or active status'
                USING ERRCODE = '42501';
        END IF;

        IF skin_classification_schema.app_role() IS DISTINCT FROM 'auth'
           AND (NEW.failed_attempts IS DISTINCT FROM OLD.failed_attempts
                OR NEW.locked_until  IS DISTINCT FROM OLD.locked_until
                OR NEW.last_login_at IS DISTINCT FROM OLD.last_login_at) THEN
            RAISE EXCEPTION 'login counters can only be changed by the login process'
                USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS users_protect_columns ON skin_classification_schema.users;
CREATE TRIGGER users_protect_columns
    BEFORE UPDATE ON skin_classification_schema.users
    FOR EACH ROW EXECUTE FUNCTION skin_classification_schema.protect_user_columns();

RESET ROLE;

-- ---------------------------------------------------------------------
-- STEP 5. Schema + table privileges, least privilege (slides 7-9)
-- ---------------------------------------------------------------------
REVOKE ALL ON ALL TABLES    IN SCHEMA skin_classification_schema FROM PUBLIC, app_rw_group, report_ro_group;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA skin_classification_schema FROM PUBLIC, app_rw_group, report_ro_group;
REVOKE ALL ON SCHEMA skin_classification_schema FROM PUBLIC;

-- USAGE = may look inside the schema. CREATE is NOT granted to anyone but the owner.
GRANT USAGE ON SCHEMA skin_classification_schema TO app_rw_group, report_ro_group;

-- Backend (app_service): read, add, update. No DELETE, no TRUNCATE, no DDL.
GRANT SELECT, INSERT ON skin_classification_schema.users TO app_rw_group;
GRANT UPDATE (first_name, last_name, middle_name, contact_number, age,
              password_hash, role, is_active,
              failed_attempts, locked_until, last_login_at)
      ON skin_classification_schema.users TO app_rw_group;     -- not user_id / username / created_at

GRANT SELECT, INSERT                 ON skin_classification_schema.login_attempts TO app_rw_group;
GRANT SELECT, INSERT, UPDATE (revoked_at, expires_at)
                                     ON skin_classification_schema.auth_sessions TO app_rw_group;
GRANT DELETE                         ON skin_classification_schema.auth_sessions TO app_rw_group;  -- expired sessions only (RLS)
GRANT SELECT, INSERT, UPDATE         ON skin_classification_schema.skin_conditions TO app_rw_group;   -- writes: admin only (RLS)
GRANT SELECT, INSERT, UPDATE         ON skin_classification_schema.model_versions TO app_rw_group;    -- writes: admin only (RLS)
GRANT SELECT, INSERT, UPDATE         ON skin_classification_schema.guidance_recommendations TO app_rw_group;
GRANT SELECT, INSERT, UPDATE (status, notes, body_area)
                                     ON skin_classification_schema.scan_records TO app_rw_group;
GRANT SELECT, INSERT, UPDATE         ON skin_classification_schema.reported_symptoms TO app_rw_group;
GRANT SELECT, INSERT                 ON skin_classification_schema.classification_results TO app_rw_group;  -- results are never edited
GRANT SELECT, INSERT, UPDATE (decision, final_condition_id, comments)
                                     ON skin_classification_schema.medical_reviews TO app_rw_group;
GRANT SELECT, INSERT                 ON skin_classification_schema.audit_logs TO app_rw_group;        -- log can never be edited
GRANT SELECT                         ON skin_classification_schema.v_scan_summary TO app_rw_group;

-- Reports page (report_reader): SELECT only, aggregated + reference data
GRANT SELECT ON skin_classification_schema.v_condition_stats        TO report_ro_group;
GRANT SELECT ON skin_classification_schema.skin_conditions          TO report_ro_group;
GRANT SELECT ON skin_classification_schema.guidance_recommendations TO report_ro_group;

-- Be explicit about what is withheld (slide 8 style):
REVOKE DELETE, TRUNCATE, REFERENCES, TRIGGER
    ON ALL TABLES IN SCHEMA skin_classification_schema FROM app_rw_group, report_ro_group;
GRANT  DELETE ON skin_classification_schema.auth_sessions TO app_rw_group;  -- re-grant the one exception

-- ---------------------------------------------------------------------
-- STEP 6. Row-Level Security (slides 12-14)
-- A role also needs the table privilege; RLS only filters rows further.
-- The backend does not own the tables, so RLS always applies to it.
-- Anything without a matching policy is denied.
-- ---------------------------------------------------------------------
-- start clean so this script can be re-run
DO $$
DECLARE p record;
BEGIN
    FOR p IN SELECT policyname, tablename FROM pg_policies
             WHERE schemaname = 'skin_classification_schema'
    LOOP
        EXECUTE format('DROP POLICY %I ON skin_classification_schema.%I', p.policyname, p.tablename);
    END LOOP;
END $$;

SET ROLE db_admin;

-- ---- users: you see/edit your own row; administrator + login code see all
ALTER TABLE skin_classification_schema.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY users_select ON skin_classification_schema.users
    FOR SELECT TO app_rw_group
    USING (user_id = skin_classification_schema.app_user_id()
           OR skin_classification_schema.app_role() IN ('administrator', 'auth'));

-- Registration may only ever create a 'patient'. Staff accounts are created
-- by an administrator.
CREATE POLICY users_insert ON skin_classification_schema.users
    FOR INSERT TO app_rw_group
    WITH CHECK (skin_classification_schema.app_role() = 'administrator'
                OR (skin_classification_schema.app_role() = 'auth' AND role = 'patient'));

CREATE POLICY users_update ON skin_classification_schema.users
    FOR UPDATE TO app_rw_group
    USING      (user_id = skin_classification_schema.app_user_id()
                OR skin_classification_schema.app_role() IN ('administrator', 'auth'))
    WITH CHECK (user_id = skin_classification_schema.app_user_id()
                OR skin_classification_schema.app_role() IN ('administrator', 'auth'));

-- ---- auth_sessions: own sessions; the login code and admin can manage any
ALTER TABLE skin_classification_schema.auth_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY sessions_select ON skin_classification_schema.auth_sessions
    FOR SELECT TO app_rw_group
    USING (user_id = skin_classification_schema.app_user_id()
           OR skin_classification_schema.app_role() IN ('administrator', 'auth'));
CREATE POLICY sessions_insert ON skin_classification_schema.auth_sessions
    FOR INSERT TO app_rw_group
    WITH CHECK (user_id = skin_classification_schema.app_user_id()
                OR skin_classification_schema.app_role() IN ('administrator', 'auth'));
CREATE POLICY sessions_update ON skin_classification_schema.auth_sessions
    FOR UPDATE TO app_rw_group
    USING (user_id = skin_classification_schema.app_user_id()
           OR skin_classification_schema.app_role() IN ('administrator', 'auth'));
CREATE POLICY sessions_delete ON skin_classification_schema.auth_sessions
    FOR DELETE TO app_rw_group
    USING ((user_id = skin_classification_schema.app_user_id()
            OR skin_classification_schema.app_role() IN ('administrator', 'auth'))
           AND (expires_at < now() OR revoked_at IS NOT NULL));      -- dead sessions only

-- ---- login_attempts: only the login code and administrator
ALTER TABLE skin_classification_schema.login_attempts ENABLE ROW LEVEL SECURITY;

CREATE POLICY attempts_select ON skin_classification_schema.login_attempts
    FOR SELECT TO app_rw_group
    USING (skin_classification_schema.app_role() IN ('administrator', 'auth'));
CREATE POLICY attempts_insert ON skin_classification_schema.login_attempts
    FOR INSERT TO app_rw_group
    WITH CHECK (skin_classification_schema.app_role() IN ('administrator', 'auth'));

-- ---- reference tables: everyone reads, only an administrator writes
ALTER TABLE skin_classification_schema.skin_conditions ENABLE ROW LEVEL SECURITY;
CREATE POLICY conditions_select ON skin_classification_schema.skin_conditions
    FOR SELECT TO app_rw_group, report_ro_group USING (true);
CREATE POLICY conditions_insert ON skin_classification_schema.skin_conditions
    FOR INSERT TO app_rw_group WITH CHECK (skin_classification_schema.app_role() = 'administrator');
CREATE POLICY conditions_update ON skin_classification_schema.skin_conditions
    FOR UPDATE TO app_rw_group
    USING (skin_classification_schema.app_role() = 'administrator')
    WITH CHECK (skin_classification_schema.app_role() = 'administrator');

ALTER TABLE skin_classification_schema.guidance_recommendations ENABLE ROW LEVEL SECURITY;
CREATE POLICY guidance_select ON skin_classification_schema.guidance_recommendations
    FOR SELECT TO app_rw_group, report_ro_group USING (true);
CREATE POLICY guidance_insert ON skin_classification_schema.guidance_recommendations
    FOR INSERT TO app_rw_group WITH CHECK (skin_classification_schema.app_role() = 'administrator');
CREATE POLICY guidance_update ON skin_classification_schema.guidance_recommendations
    FOR UPDATE TO app_rw_group
    USING (skin_classification_schema.app_role() = 'administrator')
    WITH CHECK (skin_classification_schema.app_role() = 'administrator');

ALTER TABLE skin_classification_schema.model_versions ENABLE ROW LEVEL SECURITY;
CREATE POLICY models_select ON skin_classification_schema.model_versions
    FOR SELECT TO app_rw_group USING (true);
CREATE POLICY models_insert ON skin_classification_schema.model_versions
    FOR INSERT TO app_rw_group WITH CHECK (skin_classification_schema.app_role() = 'administrator');
CREATE POLICY models_update ON skin_classification_schema.model_versions
    FOR UPDATE TO app_rw_group
    USING (skin_classification_schema.app_role() = 'administrator')
    WITH CHECK (skin_classification_schema.app_role() = 'administrator');

-- ---- scan_records: a patient sees only their own scans (the slide 12-14 example)
ALTER TABLE skin_classification_schema.scan_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY scans_select ON skin_classification_schema.scan_records
    FOR SELECT TO app_rw_group
    USING (user_id = skin_classification_schema.app_user_id()
           OR skin_classification_schema.app_role() IN ('administrator', 'medical_reviewer'));
CREATE POLICY scans_insert ON skin_classification_schema.scan_records
    FOR INSERT TO app_rw_group
    WITH CHECK (user_id = skin_classification_schema.app_user_id());
CREATE POLICY scans_update ON skin_classification_schema.scan_records
    FOR UPDATE TO app_rw_group
    USING      (user_id = skin_classification_schema.app_user_id()
                OR skin_classification_schema.app_role() IN ('administrator', 'medical_reviewer'))
    WITH CHECK (user_id = skin_classification_schema.app_user_id()
                OR skin_classification_schema.app_role() IN ('administrator', 'medical_reviewer'));

-- ---- reported_symptoms + classification_results: follow the scan's visibility
ALTER TABLE skin_classification_schema.reported_symptoms ENABLE ROW LEVEL SECURITY;

CREATE POLICY symptoms_select ON skin_classification_schema.reported_symptoms
    FOR SELECT TO app_rw_group
    USING (EXISTS (SELECT 1 FROM skin_classification_schema.scan_records s
                   WHERE s.scan_id = reported_symptoms.scan_id));      -- scan_records RLS applies here too
CREATE POLICY symptoms_insert ON skin_classification_schema.reported_symptoms
    FOR INSERT TO app_rw_group
    WITH CHECK (EXISTS (SELECT 1 FROM skin_classification_schema.scan_records s
                        WHERE s.scan_id = reported_symptoms.scan_id
                          AND (s.user_id = skin_classification_schema.app_user_id()
                               OR skin_classification_schema.app_role() = 'administrator')));
CREATE POLICY symptoms_update ON skin_classification_schema.reported_symptoms
    FOR UPDATE TO app_rw_group
    USING (EXISTS (SELECT 1 FROM skin_classification_schema.scan_records s
                   WHERE s.scan_id = reported_symptoms.scan_id
                     AND (s.user_id = skin_classification_schema.app_user_id()
                          OR skin_classification_schema.app_role() = 'administrator')));

ALTER TABLE skin_classification_schema.classification_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY results_select ON skin_classification_schema.classification_results
    FOR SELECT TO app_rw_group
    USING (EXISTS (SELECT 1 FROM skin_classification_schema.scan_records s
                   WHERE s.scan_id = classification_results.scan_id));
CREATE POLICY results_insert ON skin_classification_schema.classification_results
    FOR INSERT TO app_rw_group
    WITH CHECK (EXISTS (SELECT 1 FROM skin_classification_schema.scan_records s
                        WHERE s.scan_id = classification_results.scan_id
                          AND (s.user_id = skin_classification_schema.app_user_id()
                               OR skin_classification_schema.app_role() = 'administrator')));

-- ---- medical_reviews: written only by the reviewer, read by reviewer/admin/the scan's owner
ALTER TABLE skin_classification_schema.medical_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY reviews_select ON skin_classification_schema.medical_reviews
    FOR SELECT TO app_rw_group
    USING (skin_classification_schema.app_role() = 'administrator'
           OR reviewer_id = skin_classification_schema.app_user_id()
           OR EXISTS (SELECT 1 FROM skin_classification_schema.scan_records s
                      WHERE s.scan_id = medical_reviews.scan_id
                        AND s.user_id = skin_classification_schema.app_user_id()));
CREATE POLICY reviews_insert ON skin_classification_schema.medical_reviews
    FOR INSERT TO app_rw_group
    WITH CHECK (skin_classification_schema.app_role() = 'medical_reviewer'
                AND reviewer_id = skin_classification_schema.app_user_id());
CREATE POLICY reviews_update ON skin_classification_schema.medical_reviews
    FOR UPDATE TO app_rw_group
    USING      (skin_classification_schema.app_role() = 'medical_reviewer'
                AND reviewer_id = skin_classification_schema.app_user_id())
    WITH CHECK (skin_classification_schema.app_role() = 'medical_reviewer'
                AND reviewer_id = skin_classification_schema.app_user_id());

-- ---- audit_logs: anyone can append, only an administrator can read
ALTER TABLE skin_classification_schema.audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_select ON skin_classification_schema.audit_logs
    FOR SELECT TO app_rw_group
    USING (skin_classification_schema.app_role() = 'administrator');
CREATE POLICY audit_insert ON skin_classification_schema.audit_logs
    FOR INSERT TO app_rw_group
    WITH CHECK (user_id IS NULL
                OR user_id = skin_classification_schema.app_user_id()
                OR skin_classification_schema.app_role() IN ('administrator', 'auth'));

RESET ROLE;

-- ---------------------------------------------------------------------
-- Summary of what was created
-- ---------------------------------------------------------------------
\echo
\echo 'Roles:'
SELECT rolname, rolcanlogin AS can_login, rolsuper AS superuser, rolbypassrls AS bypass_rls
FROM pg_roles
WHERE rolname IN ('db_admin','app_service','report_reader','app_rw_group','report_ro_group')
ORDER BY rolname;

\echo 'Tables with row-level security:'
SELECT c.relname AS table, c.relrowsecurity AS rls_enabled
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'skin_classification_schema' AND c.relkind = 'r'
ORDER BY c.relname;

\echo 'Done. Next: create the first administrator account as db_admin (see SECURITY.md),'
\echo 'then run dermascreen_security_test.sql to prove allowed and blocked actions.'
