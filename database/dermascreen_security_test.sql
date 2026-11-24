-- =====================================================================
-- DermaScreen: prove the security setup works (slide 22, step 8:
-- "Test allowed and blocked actions"; slide 24, mistake 6: "Not testing
-- denied operations").
--
-- Run as a superuser AFTER dermascreen_schema.sql and dermascreen_security.sql:
--   psql -d dermascreen -f dermascreen_security_test.sql
--
-- Use a FRESH test database (the counts assume only the seed data exists).
-- Every line prints PASS or FAIL. Everything runs inside one transaction that
-- is rolled back at the end, so no test data is kept.
-- =====================================================================

\set ON_ERROR_STOP on
\set QUIET on
BEGIN;

-- --------------------------- test helper ------------------------------
-- chk(label, db_role, app user id, app role, sql, expectation)
--   expectation: 'ok'      statement must succeed
--                'error'   statement must be refused (privilege, RLS or trigger)
--                'rows:N'  statement is "SELECT count(*) ..." and must return N
CREATE FUNCTION pg_temp.chk(label text, as_role text, uid text, urole text,
                            stmt text, expect text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
    n bigint;
    res text;
BEGIN
    BEGIN                                   -- sub-transaction: always rolled back
        PERFORM set_config('app.current_user_id', coalesce(uid, ''), true);
        PERFORM set_config('app.current_role',    coalesce(urole, ''), true);
        IF as_role IS NOT NULL THEN
            EXECUTE format('SET LOCAL ROLE %I', as_role);
        END IF;

        IF expect LIKE 'rows:%' THEN
            EXECUTE stmt INTO n;
            res := CASE WHEN n = substr(expect, 6)::bigint THEN 'PASS'
                        ELSE format('FAIL (returned %s, expected %s)', n, substr(expect, 6)) END;
        ELSIF expect = 'ok' THEN
            EXECUTE stmt;
            res := 'PASS';
        ELSE
            EXECUTE stmt;
            res := 'FAIL (this was allowed but should be blocked)';
        END IF;
        RAISE EXCEPTION '__done__';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = '__done__' THEN
            NULL;
        ELSIF expect = 'error' THEN
            res := 'PASS';
        ELSE
            res := format('FAIL (%s)', SQLERRM);
        END IF;
    END;
    RETURN format('%s | %s%s', rpad(split_part(res, ' ', 1), 4), label,
                  CASE WHEN res LIKE '% %' THEN '   -> ' || substr(res, position(' ' in res) + 1) ELSE '' END);
END;
$$;

-- --------------------------- test data --------------------------------
SET search_path = skin_classification_schema;
INSERT INTO users (first_name, last_name, contact_number, age, username, password_hash, role) VALUES
  ('Alice',  'Santos', '09170000001', 21, 'alice_p',  'hash', 'patient'),            -- id = a
  ('Bob',    'Reyes',  '09170000002', 25, 'bob_pat',  'hash', 'patient'),            -- id = b
  ('Rina',   'Cruz',   '09170000003', 40, 'dr_rina',  'hash', 'medical_reviewer'),   -- id = r
  ('Admin',  'Boss',   '09170000004', 30, 'admin_01', 'hash', 'administrator');      -- id = m
INSERT INTO scan_records (user_id, image_path, age_group, duration_range, itch_score, has_swelling, has_allergy,
                          description, contact_number, image_quality, result_basis)
  SELECT user_id, 'uploads/' || username || '.jpg', '18-30', '1_3d', 5, false, false,
         'Itchy red patch on the arm for a few days', '09170000001', 'good', 'image_and_description'
  FROM users WHERE username IN ('alice_p', 'bob_pat');
INSERT INTO classification_results (scan_id, condition_id, model_id, confidence, rank)
  SELECT scan_id, 3, 1, 0.9, 1 FROM scan_records;
INSERT INTO audit_logs (action) VALUES ('test.setup');

-- ids to use below
CREATE TEMP TABLE ids AS
SELECT (SELECT user_id FROM users WHERE username = 'alice_p')  AS a,
       (SELECT user_id FROM users WHERE username = 'bob_pat')  AS b,
       (SELECT user_id FROM users WHERE username = 'dr_rina')  AS r,
       (SELECT user_id FROM users WHERE username = 'admin_01') AS m,
       (SELECT scan_id FROM scan_records s JOIN users u USING (user_id) WHERE u.username = 'alice_p') AS sa,
       (SELECT scan_id FROM scan_records s JOIN users u USING (user_id) WHERE u.username = 'bob_pat') AS sb;
SELECT a, b, r, m, sa, sb FROM ids \gset
\set QUIET off
\t on

\echo
\echo '=== 1. PATIENT (alice) through the backend account app_service ==='
SELECT pg_temp.chk('sees only her own scan',                     'app_service', :'a', 'patient', 'SELECT count(*) FROM scan_records', 'rows:1');
SELECT pg_temp.chk('cannot see another patient''s scan',         'app_service', :'a', 'patient', format('SELECT count(*) FROM scan_records WHERE scan_id = %s', :'sb'), 'rows:0');
SELECT pg_temp.chk('sees only her own user row',                 'app_service', :'a', 'patient', 'SELECT count(*) FROM users', 'rows:1');
SELECT pg_temp.chk('sees only her own prediction results',       'app_service', :'a', 'patient', 'SELECT count(*) FROM classification_results', 'rows:1');
SELECT pg_temp.chk('can read the condition list',                'app_service', :'a', 'patient', 'SELECT count(*) FROM skin_conditions', 'rows:6');
SELECT pg_temp.chk('cannot read the audit log',                  'app_service', :'a', 'patient', 'SELECT count(*) FROM audit_logs', 'rows:0');
SELECT pg_temp.chk('can add a scan for herself',                 'app_service', :'a', 'patient', format('INSERT INTO scan_records (user_id, image_path, age_group, duration_range, itch_score, has_swelling, has_allergy, description, contact_number, image_quality, result_basis) VALUES (%s, ''x.jpg'', ''18-30'', ''1_3d'', 5, false, false, ''test description here'', ''09170000001'', ''good'', ''image_and_description'')', :'a'), 'ok');
SELECT pg_temp.chk('cannot add a scan for someone else',         'app_service', :'a', 'patient', format('INSERT INTO scan_records (user_id, image_path, age_group, duration_range, itch_score, has_swelling, has_allergy, description, contact_number, image_quality, result_basis) VALUES (%s, ''x.jpg'', ''18-30'', ''1_3d'', 5, false, false, ''test description here'', ''09170000001'', ''good'', ''image_and_description'')', :'b'), 'error');
SELECT pg_temp.chk('can update her own profile (age)',           'app_service', :'a', 'patient', format('UPDATE users SET age = 22 WHERE user_id = %s', :'a'), 'ok');
SELECT pg_temp.chk('cannot promote herself to administrator',    'app_service', :'a', 'patient', format('UPDATE users SET role = ''administrator'' WHERE user_id = %s', :'a'), 'error');
SELECT pg_temp.chk('cannot reset her own failed-login counter',  'app_service', :'a', 'patient', format('UPDATE users SET failed_attempts = 1, locked_until = NULL WHERE user_id = %s', :'a'), 'error');
SELECT pg_temp.chk('cannot edit another patient''s profile',     'app_service', :'a', 'patient', format('WITH u AS (UPDATE users SET age = 99 WHERE user_id = %s RETURNING 1) SELECT count(*) FROM u', :'b'), 'rows:0');
SELECT pg_temp.chk('cannot write a medical review',              'app_service', :'a', 'patient', format('INSERT INTO medical_reviews (scan_id, reviewer_id, decision, final_condition_id) VALUES (%s, %s, ''confirmed'', 3)', :'sa', :'r'), 'error');
SELECT pg_temp.chk('cannot change the condition list',           'app_service', :'a', 'patient', 'INSERT INTO skin_conditions (code, name, category, description) VALUES (''x'',''X'',''x'',''x'')', 'error');
SELECT pg_temp.chk('DELETE is not allowed on scans',             'app_service', :'a', 'patient', 'DELETE FROM scan_records', 'error');
SELECT pg_temp.chk('DELETE is not allowed on users',             'app_service', :'a', 'patient', 'DELETE FROM users', 'error');
SELECT pg_temp.chk('TRUNCATE is not allowed',                    'app_service', :'a', 'patient', 'TRUNCATE scan_records CASCADE', 'error');
SELECT pg_temp.chk('cannot DROP a table',                        'app_service', :'a', 'patient', 'DROP TABLE users CASCADE', 'error');
SELECT pg_temp.chk('cannot create tables in the app schema',     'app_service', :'a', 'patient', 'CREATE TABLE skin_classification_schema.hack (i int)', 'error');
SELECT pg_temp.chk('cannot create tables in public',             'app_service', :'a', 'patient', 'CREATE TABLE public.hack (i int)', 'error');
SELECT pg_temp.chk('cannot edit the audit log',                  'app_service', :'a', 'patient', 'UPDATE audit_logs SET action = ''x''', 'error');
SELECT pg_temp.chk('cannot edit a prediction result',            'app_service', :'a', 'patient', 'UPDATE classification_results SET confidence = 1', 'error');

\echo
\echo '=== 2. NO CONTEXT SET (backend forgot to say who is calling) ==='
SELECT pg_temp.chk('sees no scans',                              'app_service', NULL, NULL, 'SELECT count(*) FROM scan_records', 'rows:0');
SELECT pg_temp.chk('sees no users',                              'app_service', NULL, NULL, 'SELECT count(*) FROM users', 'rows:0');

\echo
\echo '=== 3. LOGIN / REGISTER code path (app role "auth") ==='
SELECT pg_temp.chk('can look up an account by username',         'app_service', NULL, 'auth', 'SELECT count(*) FROM users WHERE username = ''alice_p''', 'rows:1');
SELECT pg_temp.chk('can register a new PATIENT',                 'app_service', NULL, 'auth', 'INSERT INTO users (first_name,last_name,contact_number,age,username,password_hash) VALUES (''New'',''User'',''09170000009'',20,''new_user'',''hash'')', 'ok');
SELECT pg_temp.chk('cannot register an administrator',           'app_service', NULL, 'auth', 'INSERT INTO users (first_name,last_name,contact_number,age,username,password_hash,role) VALUES (''Evil'',''User'',''09170000008'',20,''evil_adm'',''hash'',''administrator'')', 'error');
SELECT pg_temp.chk('can count a failed login',                   'app_service', NULL, 'auth', format('UPDATE users SET failed_attempts = 1 WHERE user_id = %s', :'a'), 'ok');
SELECT pg_temp.chk('can lock an account for 3 minutes',          'app_service', NULL, 'auth', format('UPDATE users SET failed_attempts = 5, locked_until = now() + interval ''3 minutes'' WHERE user_id = %s', :'a'), 'ok');
SELECT pg_temp.chk('can record a login attempt',                 'app_service', NULL, 'auth', 'INSERT INTO login_attempts (username_tried, was_successful) VALUES (''alice_p'', false)', 'ok');
SELECT pg_temp.chk('cannot read patient scans',                  'app_service', NULL, 'auth', 'SELECT count(*) FROM scan_records', 'rows:0');
SELECT pg_temp.chk('cannot make anyone an administrator',        'app_service', NULL, 'auth', format('UPDATE users SET role = ''administrator'' WHERE user_id = %s', :'a'), 'error');

\echo
\echo '=== 4. MEDICAL REVIEWER ==='
SELECT pg_temp.chk('sees all scans',                             'app_service', :'r', 'medical_reviewer', 'SELECT count(*) FROM scan_records', 'rows:2');
SELECT pg_temp.chk('patient names stay hidden in the scan view', 'app_service', :'r', 'medical_reviewer', 'SELECT count(*) FROM v_scan_summary WHERE username IS NOT NULL', 'rows:0');
SELECT pg_temp.chk('cannot read the users table (only own row)', 'app_service', :'r', 'medical_reviewer', 'SELECT count(*) FROM users', 'rows:1');
SELECT pg_temp.chk('can review a scan as herself',               'app_service', :'r', 'medical_reviewer', format('INSERT INTO medical_reviews (scan_id, reviewer_id, decision, final_condition_id) VALUES (%s, %s, ''confirmed'', 3)', :'sa', :'r'), 'ok');
SELECT pg_temp.chk('cannot review in someone else''s name',      'app_service', :'r', 'medical_reviewer', format('INSERT INTO medical_reviews (scan_id, reviewer_id, decision, final_condition_id) VALUES (%s, %s, ''confirmed'', 3)', :'sa', :'m'), 'error');
SELECT pg_temp.chk('cannot change roles',                        'app_service', :'r', 'medical_reviewer', format('UPDATE users SET role = ''administrator'' WHERE user_id = %s', :'r'), 'error');

\echo
\echo '=== 5. ADMINISTRATOR ==='
SELECT pg_temp.chk('sees all users',                             'app_service', :'m', 'administrator', 'SELECT count(*) FROM users', 'rows:4');
SELECT pg_temp.chk('sees all scans',                             'app_service', :'m', 'administrator', 'SELECT count(*) FROM scan_records', 'rows:2');
SELECT pg_temp.chk('can read the audit log',                     'app_service', :'m', 'administrator', 'SELECT count(*) FROM audit_logs', 'rows:1');
SELECT pg_temp.chk('can create a reviewer account',              'app_service', :'m', 'administrator', 'INSERT INTO users (first_name,last_name,contact_number,age,username,password_hash,role) VALUES (''New'',''Doc'',''09170000007'',35,''new_doc'',''hash'',''medical_reviewer'')', 'ok');
SELECT pg_temp.chk('can change a user''s role',                  'app_service', :'m', 'administrator', format('UPDATE users SET role = ''medical_reviewer'' WHERE user_id = %s', :'b'), 'ok');
SELECT pg_temp.chk('can add a skin condition',                   'app_service', :'m', 'administrator', 'INSERT INTO skin_conditions (code, name, category, description) VALUES (''wart'',''Warts'',''Viral'',''x'')', 'ok');
SELECT pg_temp.chk('still cannot DELETE users',                  'app_service', :'m', 'administrator', 'DELETE FROM users', 'error');
SELECT pg_temp.chk('still cannot DROP tables (backend owns none)', 'app_service', :'m', 'administrator', 'DROP TABLE scan_records CASCADE', 'error');

\echo
\echo '=== 6. REPORT READER (report_reader: SELECT only) ==='
SELECT pg_temp.chk('can read aggregated condition stats',        'report_reader', NULL, NULL, 'SELECT count(*) FROM v_condition_stats', 'rows:1');
SELECT pg_temp.chk('can read the condition list',                'report_reader', NULL, NULL, 'SELECT count(*) FROM skin_conditions', 'rows:6');
SELECT pg_temp.chk('cannot read users',                          'report_reader', NULL, NULL, 'SELECT count(*) FROM users', 'error');
SELECT pg_temp.chk('cannot read scan records',                   'report_reader', NULL, NULL, 'SELECT count(*) FROM scan_records', 'error');
SELECT pg_temp.chk('cannot read the scan summary view',          'report_reader', NULL, NULL, 'SELECT count(*) FROM v_scan_summary', 'error');
SELECT pg_temp.chk('cannot INSERT anything',                     'report_reader', NULL, NULL, 'INSERT INTO skin_conditions (code, name, category, description) VALUES (''x'',''X'',''x'',''x'')', 'error');
SELECT pg_temp.chk('cannot UPDATE anything',                     'report_reader', NULL, NULL, 'UPDATE skin_conditions SET name = ''x''', 'error');
SELECT pg_temp.chk('cannot DELETE anything',                     'report_reader', NULL, NULL, 'DELETE FROM skin_conditions', 'error');

\echo
\echo '=== 7. Role hygiene ==='
SELECT pg_temp.chk('app_service is not a superuser',             NULL, NULL, NULL, 'SELECT count(*) FROM pg_roles WHERE rolname IN (''app_service'',''report_reader'',''db_admin'') AND (rolsuper OR rolcreaterole OR rolcreatedb OR rolbypassrls)', 'rows:0');
SELECT pg_temp.chk('backend owns no tables',                     NULL, NULL, NULL, 'SELECT count(*) FROM pg_tables WHERE schemaname = ''skin_classification_schema'' AND tableowner <> ''db_admin''', 'rows:0');
SELECT pg_temp.chk('every table has row-level security on',      NULL, NULL, NULL, 'SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = ''skin_classification_schema'' AND c.relkind = ''r'' AND NOT c.relrowsecurity', 'rows:0');

ROLLBACK;