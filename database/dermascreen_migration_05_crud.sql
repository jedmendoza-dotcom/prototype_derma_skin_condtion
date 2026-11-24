-- DermaScreen migration 05: lets a patient delete their OWN screenings (dashboard CRUD).
-- Safe to run twice. Run in pgAdmin as postgres.
-- Update uses the existing `notes` column (already allowed). Delete needs the permission below.
-- Deleting a scan also deletes its saved results (ON DELETE CASCADE).
GRANT DELETE ON skin_classification_schema.scan_records TO app_rw_group;

DROP POLICY IF EXISTS scans_delete ON skin_classification_schema.scan_records;
CREATE POLICY scans_delete ON skin_classification_schema.scan_records
    FOR DELETE TO app_rw_group
    USING (user_id = skin_classification_schema.app_user_id()
           AND status <> 'reviewed');          -- a screening a doctor already reviewed is kept

SELECT policyname, cmd FROM pg_policies
WHERE schemaname = 'skin_classification_schema' AND tablename = 'scan_records' ORDER BY policyname;