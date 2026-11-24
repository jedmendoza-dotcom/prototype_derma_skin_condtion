-- DermaScreen migration 03: results page support. Safe to run twice. Run in pgAdmin as postgres.
ALTER TABLE skin_classification_schema.skin_conditions
    ADD COLUMN IF NOT EXISTS reference_url    TEXT,
    ADD COLUMN IF NOT EXISTS reference_source VARCHAR(60);

ALTER TABLE skin_classification_schema.scan_records
    ADD COLUMN IF NOT EXISTS result_method VARCHAR(20) NOT NULL DEFAULT 'rules_only';

DO $$ BEGIN
  ALTER TABLE skin_classification_schema.scan_records
    ADD CONSTRAINT scan_method_chk CHECK (result_method IN ('rules_only','model_and_rules'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- "More details" links. Open each one in a browser once to confirm it works.
UPDATE skin_classification_schema.skin_conditions SET reference_source = 'DermNet NZ',
  reference_url = CASE code
    WHEN 'acne'     THEN 'https://dermnetnz.org/topics/acne-vulgaris'
    WHEN 'eczema'   THEN 'https://dermnetnz.org/topics/atopic-dermatitis'
    WHEN 'tinea'    THEN 'https://dermnetnz.org/topics/tinea-corporis'
    WHEN 'scabies'  THEN 'https://dermnetnz.org/topics/scabies'
    WHEN 'impetigo' THEN 'https://dermnetnz.org/topics/impetigo'
    WHEN 'melasma'  THEN 'https://dermnetnz.org/topics/melasma'
  END
WHERE reference_url IS NULL;

SELECT code, reference_url FROM skin_classification_schema.skin_conditions ORDER BY code;