-- ═══════════════════════════════════════════════════════════════════
-- Etch — Soft-delete cleanup (hard-delete after 30 days)
-- ═══════════════════════════════════════════════════════════════════
-- Run this in Supabase Dashboard → SQL Editor.
--
-- Notes are "soft-deleted" by setting `deleted_at` instead of removing
-- the row. Without cleanup those rows accumulate forever, inflating
-- the notes table. This migration:
--   1. Adds a function that hard-deletes notes whose deleted_at is
--      older than 30 days, along with their storage-bucket attachments.
--   2. Schedules it to run nightly via pg_cron.
--
-- Requires: the pg_cron extension (enable via Supabase Dashboard →
-- Database → Extensions → pg_cron). It runs in the postgres
-- database by default.
-- ═══════════════════════════════════════════════════════════════════

-- Enable pg_cron (idempotent)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ── Cleanup function ─────────────────────────────────────────────
-- Hard-deletes notes whose deleted_at is more than 30 days old.
-- note_attachments rows cascade via FK, but the actual files in the
-- Storage bucket have to be removed separately — we collect their
-- storage_paths and let a downstream Edge Function / cron handle the
-- bucket cleanup. For now the DB is self-consistent.

CREATE OR REPLACE FUNCTION cleanup_soft_deleted_notes(retention_days INT DEFAULT 30)
RETURNS TABLE(notes_deleted BIGINT, attachment_paths TEXT[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  cutoff TIMESTAMPTZ := now() - (retention_days || ' days')::interval;
  notes_count BIGINT;
  paths       TEXT[];
BEGIN
  -- Collect storage paths before deleting so callers can clean the bucket
  SELECT COALESCE(array_agg(na.storage_path) FILTER (WHERE na.storage_path IS NOT NULL), '{}'::text[])
    INTO paths
    FROM note_attachments na
    JOIN notes n ON n.id = na.note_id
    WHERE n.deleted_at IS NOT NULL AND n.deleted_at < cutoff;

  -- Hard-delete the notes. note_attachments rows cascade if the FK is
  -- ON DELETE CASCADE; otherwise remove them explicitly first.
  DELETE FROM note_attachments
    WHERE note_id IN (
      SELECT id FROM notes WHERE deleted_at IS NOT NULL AND deleted_at < cutoff
    );

  DELETE FROM notes
    WHERE deleted_at IS NOT NULL AND deleted_at < cutoff;
  GET DIAGNOSTICS notes_count = ROW_COUNT;

  RETURN QUERY SELECT notes_count, paths;
END;
$$;

-- ── Schedule: run daily at 03:15 UTC ─────────────────────────────
-- The unique cron job name lets this migration be re-run safely.
DO $$ BEGIN
  -- Remove any previous schedule for this job (safe if none exists)
  PERFORM cron.unschedule('etch-cleanup-soft-deleted-notes')
    WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'etch-cleanup-soft-deleted-notes'
    );
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'etch-cleanup-soft-deleted-notes',
  '15 3 * * *',                       -- 03:15 UTC daily
  $$ SELECT cleanup_soft_deleted_notes(30); $$
);

-- ── Manual-run helper ────────────────────────────────────────────
-- Convenience view the website admin panel can query to see pending
-- cleanup volume without running the delete.
CREATE OR REPLACE VIEW soft_deleted_note_counts AS
SELECT
  p.org_id,
  COUNT(n.id)                                                     AS total_soft_deleted,
  COUNT(n.id) FILTER (WHERE n.deleted_at < now() - interval '30 days') AS ready_to_purge
FROM notes n
JOIN sessions s ON s.id = n.session_id
JOIN projects p ON p.id = s.project_id
WHERE n.deleted_at IS NOT NULL
GROUP BY p.org_id;

-- ── Notes for the admin ──────────────────────────────────────────
-- The function returns storage_path[] for any attachments on purged
-- notes. Supabase Storage doesn't auto-delete bucket files when DB
-- rows are removed. To close the loop, either:
--   (a) Call the function manually and delete the returned paths via
--       the Storage API / a scheduled Edge Function, or
--   (b) Leave them — they'll be orphaned but Supabase still bills for
--       them. Revisit with an Edge Function when volume matters.
