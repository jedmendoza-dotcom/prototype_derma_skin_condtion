-- =====================================================================
-- DermaScreen: PostgreSQL database schema
-- ML-based skin condition screening system
--
-- Run (creates the database, then the schema inside it):
--   createdb dermascreen
--   psql -d dermascreen -f dermascreen_schema.sql
--
-- Rules this schema enforces:
--   * Every table lives in the schema  skin_classification_schema
--   * Passwords are stored only as hashes (bcrypt/argon2), never plain text
--   * Roles: patient | administrator | medical_reviewer
--   * Login lockout: 5 failed attempts -> locked for 3 minutes (users table)
--   * "Remember me" sessions last 7 days (auth_sessions table)
--   * Results are a SCREENING, not a diagnosis; a medical reviewer can confirm
--   * Deleting a user removes their scans, symptoms, results and reviews
--     (ON DELETE CASCADE); conditions/models are protected (RESTRICT)
-- =====================================================================

BEGIN;

CREATE SCHEMA IF NOT EXISTS skin_classification_schema;
SET LOCAL search_path TO skin_classification_schema, public;

-- ---------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------
CREATE TYPE skin_classification_schema.user_role AS ENUM
    ('patient', 'administrator', 'medical_reviewer');

CREATE TYPE skin_classification_schema.scan_status AS ENUM
    ('uploaded', 'processing', 'completed', 'failed', 'reviewed');

CREATE TYPE skin_classification_schema.severity_level AS ENUM
    ('mild', 'moderate', 'severe');

CREATE TYPE skin_classification_schema.urgency_level AS ENUM
    ('self_care', 'see_doctor_soon', 'see_doctor_urgently');

CREATE TYPE skin_classification_schema.review_decision AS ENUM
    ('confirmed', 'corrected', 'rejected');

-- ---------------------------------------------------------------------
-- Helper: keep updated_at current
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION skin_classification_schema.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------
-- 1. users
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.users (
    user_id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name       VARCHAR(40)  NOT NULL,
    last_name        VARCHAR(40)  NOT NULL,
    middle_name      VARCHAR(40),                        -- optional
    contact_number   VARCHAR(16)  NOT NULL,
    age              SMALLINT     NOT NULL,
    username         VARCHAR(20)  NOT NULL,
    password_hash    TEXT         NOT NULL,              -- bcrypt / argon2 hash
    role             skin_classification_schema.user_role NOT NULL DEFAULT 'patient',
    is_active        BOOLEAN      NOT NULL DEFAULT TRUE,
    privacy_consent_at TIMESTAMPTZ NOT NULL DEFAULT now(), -- Data Privacy Act (RA 10173) consent
    failed_attempts  SMALLINT     NOT NULL DEFAULT 0,    -- lockout counter
    locked_until     TIMESTAMPTZ,                        -- NULL = not locked
    last_login_at    TIMESTAMPTZ,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT users_age_chk       CHECK (age BETWEEN 1 AND 120),
    CONSTRAINT users_username_chk  CHECK (username ~ '^[A-Za-z0-9_]{4,20}$'),
    CONSTRAINT users_contact_chk   CHECK (contact_number ~ '^(09[0-9]{9}|\+639[0-9]{9})$'),
    CONSTRAINT users_failed_chk    CHECK (failed_attempts BETWEEN 0 AND 5),
    CONSTRAINT users_name_chk      CHECK (length(btrim(first_name)) >= 2 AND length(btrim(last_name)) >= 2)
);
-- usernames are case-insensitive unique ("Demo" and "demo" are the same)
CREATE UNIQUE INDEX users_username_uq ON skin_classification_schema.users (lower(username));
CREATE INDEX users_role_idx           ON skin_classification_schema.users (role);

CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON skin_classification_schema.users
    FOR EACH ROW EXECUTE FUNCTION skin_classification_schema.set_updated_at();

-- ---------------------------------------------------------------------
-- 2. auth_sessions   ("remember me for 7 days" + JWT refresh tokens)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.auth_sessions (
    session_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT      NOT NULL
                  REFERENCES skin_classification_schema.users (user_id) ON DELETE CASCADE,
    token_hash    TEXT        NOT NULL UNIQUE,           -- store a hash of the token, not the token
    remember_me   BOOLEAN     NOT NULL DEFAULT FALSE,
    user_agent    TEXT,
    ip_address    INET,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at    TIMESTAMPTZ NOT NULL,                  -- app sets now()+7 days when remember_me
    revoked_at    TIMESTAMPTZ,                           -- set on logout

    CONSTRAINT auth_sessions_expiry_chk CHECK (expires_at > created_at)
);
CREATE INDEX auth_sessions_user_idx    ON skin_classification_schema.auth_sessions (user_id);
CREATE INDEX auth_sessions_expires_idx ON skin_classification_schema.auth_sessions (expires_at);

-- ---------------------------------------------------------------------
-- 3. login_attempts   (audit trail + per-IP lockout support)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.login_attempts (
    attempt_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id       BIGINT REFERENCES skin_classification_schema.users (user_id) ON DELETE SET NULL,
    username_tried VARCHAR(40) NOT NULL,                 -- kept even if the user does not exist
    ip_address    INET,
    was_successful BOOLEAN    NOT NULL,
    attempted_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX login_attempts_user_time_idx ON skin_classification_schema.login_attempts (user_id, attempted_at DESC);
CREATE INDEX login_attempts_ip_time_idx   ON skin_classification_schema.login_attempts (ip_address, attempted_at DESC);

-- ---------------------------------------------------------------------
-- 4. skin_conditions   (the 4-7 conditions the model can predict)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.skin_conditions (
    condition_id   SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    code           VARCHAR(30)  NOT NULL UNIQUE,         -- must match the ML model's class label
    name           VARCHAR(80)  NOT NULL UNIQUE,
    category       VARCHAR(30)  NOT NULL,                -- inflammatory, fungal, bacterial...
    description    TEXT         NOT NULL,
    common_signs   TEXT[]       NOT NULL DEFAULT '{}',
    image_path     TEXT,                                 -- reference photo shown on the Home page
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE TRIGGER skin_conditions_set_updated_at
    BEFORE UPDATE ON skin_classification_schema.skin_conditions
    FOR EACH ROW EXECUTE FUNCTION skin_classification_schema.set_updated_at();

-- ---------------------------------------------------------------------
-- 5. model_versions   (which trained model produced a result)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.model_versions (
    model_id      SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name          VARCHAR(60)  NOT NULL,                 -- e.g. MobileNetV2, EfficientNet-B0
    version       VARCHAR(20)  NOT NULL,
    training_data VARCHAR(120),                          -- e.g. HAM10000 + ISIC subset
    accuracy      NUMERIC(5,4),                          -- 0.0000 - 1.0000
    is_active     BOOLEAN      NOT NULL DEFAULT FALSE,
    trained_at    DATE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT model_versions_uq       UNIQUE (name, version),
    CONSTRAINT model_versions_acc_chk  CHECK (accuracy IS NULL OR accuracy BETWEEN 0 AND 1)
);
-- only ONE model can be active at a time
CREATE UNIQUE INDEX model_versions_one_active_uq
    ON skin_classification_schema.model_versions (is_active) WHERE is_active;

-- ---------------------------------------------------------------------
-- 6. scan_records   (one uploaded skin photo)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.scan_records (
    scan_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id         BIGINT NOT NULL
                    REFERENCES skin_classification_schema.users (user_id) ON DELETE CASCADE,
    image_path      TEXT        NOT NULL,                -- file path / object-storage key
    image_sha256    CHAR(64),                            -- detect duplicate uploads
    body_area       VARCHAR(40),                         -- face, arm, leg, back...
    notes           TEXT,
    status          skin_classification_schema.scan_status NOT NULL DEFAULT 'uploaded',
    scanned_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- symptom intake (everything is required; see dermascreen_migration_02_intake.sql)
    age_group       VARCHAR(10) NOT NULL,                -- age of the person with the skin problem
    duration_range  VARCHAR(10) NOT NULL,                -- how long they have had it
    itch_score      SMALLINT    NOT NULL,                -- 0 = none ... 10 = unbearable
    has_swelling    BOOLEAN     NOT NULL,
    has_allergy     BOOLEAN     NOT NULL,
    allergy_details VARCHAR(200),
    description     TEXT        NOT NULL,                -- what the user feels, in their own words
    contact_number  VARCHAR(13) NOT NULL,
    -- photo quality check (done by the backend)
    image_quality   VARCHAR(8)  NOT NULL,                -- good | poor
    quality_issue   VARCHAR(12),                         -- blurry | too_dark | too_bright | too_small
    quality_score   NUMERIC(8,2),
    retake_count    SMALLINT    NOT NULL DEFAULT 0,
    result_basis    VARCHAR(24) NOT NULL,                -- image_and_description | description_only

    CONSTRAINT scan_records_sha_chk CHECK (image_sha256 IS NULL OR image_sha256 ~ '^[0-9a-f]{64}$'),
    CONSTRAINT scan_age_group_chk  CHECK (age_group IN ('0-1','2-5','6-12','13-17','18-30','31-45','46-60','61+')),
    CONSTRAINT scan_duration_chk   CHECK (duration_range IN ('lt_1d','1_3d','4_7d','1_2w','3_4w','1_3m','gt_3m')),
    CONSTRAINT scan_itch_chk       CHECK (itch_score BETWEEN 0 AND 10),
    CONSTRAINT scan_description_chk CHECK (char_length(btrim(description)) BETWEEN 10 AND 1000),
    CONSTRAINT scan_contact_chk    CHECK (contact_number ~ '^(09[0-9]{9}|\+639[0-9]{9})$'),
    CONSTRAINT scan_quality_chk    CHECK (image_quality IN ('good','poor')),
    CONSTRAINT scan_quality_issue_chk CHECK (quality_issue IS NULL OR quality_issue IN ('blurry','too_dark','too_bright','too_small')),
    CONSTRAINT scan_retake_chk     CHECK (retake_count BETWEEN 0 AND 5),
    CONSTRAINT scan_basis_values_chk CHECK (result_basis IN ('image_and_description','description_only')),
    CONSTRAINT scan_allergy_detail_chk CHECK (NOT has_allergy OR char_length(btrim(coalesce(allergy_details, ''))) > 0),
    CONSTRAINT scan_basis_chk      CHECK ((image_quality = 'poor') = (result_basis = 'description_only'))
);
CREATE INDEX scan_records_user_time_idx ON skin_classification_schema.scan_records (user_id, scanned_at DESC);
CREATE INDEX scan_records_status_idx    ON skin_classification_schema.scan_records (status);

CREATE TRIGGER scan_records_set_updated_at
    BEFORE UPDATE ON skin_classification_schema.scan_records
    FOR EACH ROW EXECUTE FUNCTION skin_classification_schema.set_updated_at();

-- ---------------------------------------------------------------------
-- 7. reported_symptoms   (what the user says they feel, per scan)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.reported_symptoms (
    symptom_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    scan_id       BIGINT NOT NULL
                  REFERENCES skin_classification_schema.scan_records (scan_id) ON DELETE CASCADE,
    symptom       VARCHAR(60)  NOT NULL,                 -- itching, pain, burning, bleeding...
    severity      skin_classification_schema.severity_level,
    duration_days SMALLINT,
    is_spreading  BOOLEAN,
    details       TEXT,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT reported_symptoms_days_chk CHECK (duration_days IS NULL OR duration_days BETWEEN 0 AND 3650),
    CONSTRAINT reported_symptoms_uq       UNIQUE (scan_id, symptom)
);
CREATE INDEX reported_symptoms_scan_idx ON skin_classification_schema.reported_symptoms (scan_id);

-- ---------------------------------------------------------------------
-- 8. classification_results   (model output: ranked predictions per scan)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.classification_results (
    result_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    scan_id       BIGINT   NOT NULL
                  REFERENCES skin_classification_schema.scan_records (scan_id) ON DELETE CASCADE,
    condition_id  SMALLINT NOT NULL
                  REFERENCES skin_classification_schema.skin_conditions (condition_id) ON DELETE RESTRICT,
    model_id      SMALLINT NOT NULL
                  REFERENCES skin_classification_schema.model_versions (model_id) ON DELETE RESTRICT,
    confidence    NUMERIC(5,4) NOT NULL,                 -- 0.0000 - 1.0000
    rank          SMALLINT     NOT NULL DEFAULT 1,       -- 1 = top prediction
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT classification_results_conf_chk CHECK (confidence BETWEEN 0 AND 1),
    CONSTRAINT classification_results_rank_chk CHECK (rank BETWEEN 1 AND 7),
    CONSTRAINT classification_results_scan_cond_uq UNIQUE (scan_id, condition_id),
    CONSTRAINT classification_results_scan_rank_uq UNIQUE (scan_id, rank)
);
CREATE INDEX classification_results_condition_idx ON skin_classification_schema.classification_results (condition_id);

-- ---------------------------------------------------------------------
-- 9. guidance_recommendations   (what to do next, per condition)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.guidance_recommendations (
    guidance_id   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    condition_id  SMALLINT NOT NULL
                  REFERENCES skin_classification_schema.skin_conditions (condition_id) ON DELETE CASCADE,
    severity      skin_classification_schema.severity_level NOT NULL DEFAULT 'mild',
    urgency       skin_classification_schema.urgency_level  NOT NULL DEFAULT 'self_care',
    title         VARCHAR(120) NOT NULL,
    advice        TEXT         NOT NULL,
    see_doctor_when TEXT,
    created_by    BIGINT REFERENCES skin_classification_schema.users (user_id) ON DELETE SET NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),

    CONSTRAINT guidance_condition_severity_uq UNIQUE (condition_id, severity)
);
CREATE TRIGGER guidance_set_updated_at
    BEFORE UPDATE ON skin_classification_schema.guidance_recommendations
    FOR EACH ROW EXECUTE FUNCTION skin_classification_schema.set_updated_at();

-- ---------------------------------------------------------------------
-- 10. medical_reviews   (Medical Reviewer confirms / corrects a result)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.medical_reviews (
    review_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    scan_id       BIGINT NOT NULL
                  REFERENCES skin_classification_schema.scan_records (scan_id) ON DELETE CASCADE,
    reviewer_id   BIGINT NOT NULL
                  REFERENCES skin_classification_schema.users (user_id) ON DELETE RESTRICT,
    decision      skin_classification_schema.review_decision NOT NULL,
    final_condition_id SMALLINT
                  REFERENCES skin_classification_schema.skin_conditions (condition_id) ON DELETE RESTRICT,
    comments      TEXT,
    reviewed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT medical_reviews_one_per_scan_uq UNIQUE (scan_id),
    -- confirmed/corrected must name the final condition; rejected must not
    CONSTRAINT medical_reviews_final_chk CHECK (
        (decision = 'rejected' AND final_condition_id IS NULL) OR
        (decision <> 'rejected' AND final_condition_id IS NOT NULL)
    )
);
CREATE INDEX medical_reviews_reviewer_idx ON skin_classification_schema.medical_reviews (reviewer_id);

-- Only users with the medical_reviewer role may be reviewers.
CREATE OR REPLACE FUNCTION skin_classification_schema.check_reviewer_role()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM skin_classification_schema.users
        WHERE user_id = NEW.reviewer_id AND role = 'medical_reviewer' AND is_active
    ) THEN
        RAISE EXCEPTION 'user % is not an active medical_reviewer', NEW.reviewer_id;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER medical_reviews_check_reviewer
    BEFORE INSERT OR UPDATE OF reviewer_id ON skin_classification_schema.medical_reviews
    FOR EACH ROW EXECUTE FUNCTION skin_classification_schema.check_reviewer_role();

-- ---------------------------------------------------------------------
-- 11. audit_logs   (who did what: admin actions, reviews, deletions)
-- ---------------------------------------------------------------------
CREATE TABLE skin_classification_schema.audit_logs (
    log_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT REFERENCES skin_classification_schema.users (user_id) ON DELETE SET NULL,
    action      VARCHAR(60) NOT NULL,                    -- 'user.created', 'scan.deleted'...
    entity      VARCHAR(40),
    entity_id   BIGINT,
    details     JSONB,
    ip_address  INET,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_logs_user_time_idx   ON skin_classification_schema.audit_logs (user_id, created_at DESC);
CREATE INDEX audit_logs_entity_idx      ON skin_classification_schema.audit_logs (entity, entity_id);

-- ---------------------------------------------------------------------
-- Convenience view: a scan with its top prediction and review
-- ---------------------------------------------------------------------
-- security_invoker = the CALLER's permissions and row-level security apply
-- (needs PostgreSQL 15+). LEFT JOIN users so a medical reviewer, who may not
-- read the users table, still sees scans (patient name simply stays hidden).
CREATE VIEW skin_classification_schema.v_scan_summary
WITH (security_invoker = true) AS
SELECT s.scan_id,
       s.user_id,
       u.username,
       s.scanned_at,
       s.status,
       c.name        AS top_condition,
       r.confidence  AS top_confidence,
       mr.decision   AS review_decision,
       fc.name       AS final_condition
FROM skin_classification_schema.scan_records s
LEFT JOIN skin_classification_schema.users u ON u.user_id = s.user_id
LEFT JOIN skin_classification_schema.classification_results r
       ON r.scan_id = s.scan_id AND r.rank = 1
LEFT JOIN skin_classification_schema.skin_conditions c ON c.condition_id = r.condition_id
LEFT JOIN skin_classification_schema.medical_reviews mr ON mr.scan_id = s.scan_id
LEFT JOIN skin_classification_schema.skin_conditions fc ON fc.condition_id = mr.final_condition_id;

-- ---------------------------------------------------------------------
-- De-identified statistics for the reports page (no names, no user ids).
-- Runs with the view OWNER's rights on purpose, so the read-only reporting
-- role can see these totals without any access to the underlying tables.
-- ---------------------------------------------------------------------
CREATE VIEW skin_classification_schema.v_condition_stats AS
SELECT c.name                            AS condition,
       date_trunc('month', r.created_at)::date AS month,
       count(*)                          AS predictions,
       round(avg(r.confidence), 4)       AS avg_confidence
FROM skin_classification_schema.classification_results r
JOIN skin_classification_schema.skin_conditions c USING (condition_id)
WHERE r.rank = 1
GROUP BY c.name, date_trunc('month', r.created_at)::date;

-- ---------------------------------------------------------------------
-- Seed data: the six conditions shown on the Home page + model + guidance
-- ---------------------------------------------------------------------
INSERT INTO skin_classification_schema.skin_conditions (code, name, category, description, common_signs, image_path) VALUES
 ('acne',     'Acne Vulgaris',              'Inflammatory',
  'Clogged pores and inflammation causing pimples, blackheads and cysts on the face, chest and back.',
  ARRAY['Pimples','Blackheads','Oily skin','Scarring'],        'assets/images/conditions/acne.jpg'),
 ('eczema',   'Atopic Dermatitis (Eczema)', 'Inflammatory',
  'A long-term condition that leaves the skin dry, itchy and inflamed, often triggered by heat, sweat and dust.',
  ARRAY['Intense itching','Dry patches','Redness','Thickened skin'], 'assets/images/conditions/eczema.jpg'),
 ('tinea',    'Tinea (Ringworm)',           'Fungal',
  'Fungal infection common in warm, humid climates causing scaly, itchy, ring-shaped patches.',
  ARRAY['Ring-shaped rash','Scaling','Itching','Clearer centre'], 'assets/images/conditions/tinea.jpg'),
 ('scabies',  'Scabies',                    'Parasitic',
  'Caused by mites that burrow into the skin; spreads through prolonged skin contact and shared bedding.',
  ARRAY['Night-time itching','Burrow lines','Small bumps','Between fingers'], 'assets/images/conditions/scabies.jpg'),
 ('impetigo', 'Impetigo',                   'Bacterial',
  'A contagious bacterial skin infection, most common in children, often starting from scratched bites or wounds.',
  ARRAY['Red sores','Honey-coloured crusts','Blisters','Itching'], 'assets/images/conditions/impetigo.jpg'),
 ('melasma',  'Melasma',                    'Pigmentation',
  'Brown or grey-brown patches on the face, linked to sun exposure and hormones.',
  ARRAY['Symmetrical patches','Darkens in the sun','Painless','Face area'], 'assets/images/conditions/melasma.jpg');

INSERT INTO skin_classification_schema.model_versions (name, version, training_data, is_active) VALUES
 ('MobileNetV2', '0.1', 'HAM10000 / ISIC subset (placeholder)', TRUE);

-- General guidance (mild). Reviewed wording should come from a dermatologist.
INSERT INTO skin_classification_schema.guidance_recommendations (condition_id, severity, urgency, title, advice, see_doctor_when)
SELECT condition_id, 'mild', 'self_care', 'General skin care guidance',
       'Keep the area clean and dry, avoid scratching, and avoid sharing towels or bedding. This is a screening result, not a diagnosis.',
       'See a doctor if it spreads, becomes painful, bleeds, oozes, or does not improve within 1-2 weeks.'
FROM skin_classification_schema.skin_conditions;

COMMIT;

-- ---------------------------------------------------------------------
-- IMPORTANT: create the first administrator from the API (so the password
-- is hashed with bcrypt/argon2). Do NOT insert plain-text passwords here.
-- ---------------------------------------------------------------------