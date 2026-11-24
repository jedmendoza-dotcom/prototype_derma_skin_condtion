-- =====================================================================
-- Migration 02: symptom intake + photo quality on scan_records
--
-- For a database that is ALREADY loaded with dermascreen_schema.sql.
-- (A fresh install does not need this file: the same columns are now in
--  dermascreen_schema.sql.)  Safe to run twice.
--
-- Run in pgAdmin: Query Tool on the "dermascreen" database, as postgres.
-- No change to dermascreen_security.sql is needed: the backend account already
-- has table-level SELECT / INSERT on scan_records, which covers new columns,
-- and the row-level-security policies are unchanged.
--
-- NOTE: the new required columns are NOT NULL, so scan_records must be empty
-- (it is, until the /scans endpoint is used). If you already have test rows:
--   DELETE FROM skin_classification_schema.scan_records;
-- =====================================================================
SET search_path = skin_classification_schema;

ALTER TABLE scan_records
    ADD COLUMN IF NOT EXISTS age_group       VARCHAR(10) NOT NULL
        CONSTRAINT scan_age_group_chk CHECK (age_group IN ('0-1','2-5','6-12','13-17','18-30','31-45','46-60','61+')),
    ADD COLUMN IF NOT EXISTS duration_range  VARCHAR(10) NOT NULL
        CONSTRAINT scan_duration_chk CHECK (duration_range IN ('lt_1d','1_3d','4_7d','1_2w','3_4w','1_3m','gt_3m')),
    ADD COLUMN IF NOT EXISTS itch_score      SMALLINT    NOT NULL
        CONSTRAINT scan_itch_chk CHECK (itch_score BETWEEN 0 AND 10),
    ADD COLUMN IF NOT EXISTS has_swelling    BOOLEAN     NOT NULL,
    ADD COLUMN IF NOT EXISTS has_allergy     BOOLEAN     NOT NULL,
    ADD COLUMN IF NOT EXISTS allergy_details VARCHAR(200),
    ADD COLUMN IF NOT EXISTS description     TEXT        NOT NULL
        CONSTRAINT scan_description_chk CHECK (char_length(btrim(description)) BETWEEN 10 AND 1000),
    ADD COLUMN IF NOT EXISTS contact_number  VARCHAR(13) NOT NULL
        CONSTRAINT scan_contact_chk CHECK (contact_number ~ '^(09[0-9]{9}|\+639[0-9]{9})$'),
    ADD COLUMN IF NOT EXISTS image_quality   VARCHAR(8)  NOT NULL
        CONSTRAINT scan_quality_chk CHECK (image_quality IN ('good','poor')),
    ADD COLUMN IF NOT EXISTS quality_issue   VARCHAR(12)
        CONSTRAINT scan_quality_issue_chk CHECK (quality_issue IS NULL OR quality_issue IN ('blurry','too_dark','too_bright','too_small')),
    ADD COLUMN IF NOT EXISTS quality_score   NUMERIC(8,2),
    ADD COLUMN IF NOT EXISTS retake_count    SMALLINT    NOT NULL DEFAULT 0
        CONSTRAINT scan_retake_chk CHECK (retake_count BETWEEN 0 AND 5),
    ADD COLUMN IF NOT EXISTS result_basis    VARCHAR(24) NOT NULL
        CONSTRAINT scan_basis_values_chk CHECK (result_basis IN ('image_and_description','description_only'));

-- rules that involve more than one column
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scan_allergy_detail_chk'
                   AND conrelid = 'skin_classification_schema.scan_records'::regclass) THEN
        ALTER TABLE scan_records ADD CONSTRAINT scan_allergy_detail_chk
            CHECK (NOT has_allergy OR char_length(btrim(coalesce(allergy_details, ''))) > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'scan_basis_chk'
                   AND conrelid = 'skin_classification_schema.scan_records'::regclass) THEN
        -- a poor photo means the result is based on the description only (and the reverse)
        ALTER TABLE scan_records ADD CONSTRAINT scan_basis_chk
            CHECK ((image_quality = 'poor') = (result_basis = 'description_only'));
    END IF;
END $$;