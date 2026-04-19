-- ═══════════════════════════════════════════════════════════════════
-- Etch — Seat & Storage Enforcement (server-side)
-- ═══════════════════════════════════════════════════════════════════
-- Run this in Supabase Dashboard → SQL Editor.
--
-- Adds BEFORE-INSERT triggers that prevent the app from exceeding the
-- org's subscription limits even if the client-side checks are bypassed.
-- ═══════════════════════════════════════════════════════════════════

-- ── Seat enforcement ─────────────────────────────────────────────
-- Block new org_members insertions when the org is at or over its
-- seats_allowed cap. Runs as SECURITY DEFINER so it can read
-- organizations.seats_allowed regardless of the caller's RLS policies.

CREATE OR REPLACE FUNCTION enforce_org_seat_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_count INT;
  max_seats     INT;
  sub_status    TEXT;
BEGIN
  SELECT seats_allowed, subscription_status
    INTO max_seats, sub_status
    FROM organizations
    WHERE id = NEW.org_id;

  -- No row found — reject, something's wrong with the org reference
  IF max_seats IS NULL THEN
    RAISE EXCEPTION 'Organization not found or has no active plan.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Zero seats = no active subscription. Only allow the founder insert
  -- (the very first member, usually the creator setting up the org).
  IF max_seats = 0 THEN
    SELECT COUNT(*) INTO current_count FROM org_members WHERE org_id = NEW.org_id;
    IF current_count > 0 THEN
      RAISE EXCEPTION 'This organization needs an active subscription before inviting members.'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  -- Subscription not active (past_due / canceled) — still allow existing
  -- members to be re-referenced (UPSERT-style) but block NEW joins.
  IF sub_status IS NOT NULL AND sub_status NOT IN ('active', 'trialing') THEN
    RAISE EXCEPTION 'Subscription is not active (status: %). Ask the admin to update billing.', sub_status
      USING ERRCODE = 'check_violation';
  END IF;

  -- Count existing members and compare to cap
  SELECT COUNT(*) INTO current_count FROM org_members WHERE org_id = NEW.org_id;
  IF current_count >= max_seats THEN
    RAISE EXCEPTION 'Organization has reached its seat limit (%). Ask the admin to upgrade the plan.', max_seats
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_org_seat_limit_tr ON org_members;
CREATE TRIGGER enforce_org_seat_limit_tr
  BEFORE INSERT ON org_members
  FOR EACH ROW EXECUTE FUNCTION enforce_org_seat_limit();


-- ── Storage quota enforcement ────────────────────────────────────
-- Block uploads into note_attachments when the org's total storage
-- usage would exceed storage_bytes_allowed. Uses the same pattern —
-- BEFORE INSERT trigger that consults the parent org's plan.

CREATE OR REPLACE FUNCTION enforce_org_storage_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  max_bytes    BIGINT;
  current_used BIGINT;
  note_org_id  UUID;
BEGIN
  -- Walk the chain: note_attachments → notes → sessions → projects → organizations
  SELECT o.id, o.storage_bytes_allowed
    INTO note_org_id, max_bytes
    FROM notes n
    JOIN sessions s  ON s.id = n.session_id
    JOIN projects p  ON p.id = s.project_id
    JOIN organizations o ON o.id = p.org_id
    WHERE n.id = NEW.note_id;

  IF note_org_id IS NULL THEN
    -- Couldn't resolve org — reject; something's inconsistent
    RAISE EXCEPTION 'Cannot resolve organization for this attachment.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- If plan has no quota, block all uploads (free tier)
  IF max_bytes IS NULL OR max_bytes = 0 THEN
    RAISE EXCEPTION 'No storage allowed on this plan. Upgrade to enable attachments.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Sum existing bytes + this upload's size
  SELECT COALESCE(SUM(na.file_size), 0) INTO current_used
    FROM note_attachments na
    JOIN notes n ON n.id = na.note_id
    JOIN sessions s ON s.id = n.session_id
    JOIN projects p ON p.id = s.project_id
    WHERE p.org_id = note_org_id;

  IF current_used + COALESCE(NEW.file_size, 0) > max_bytes THEN
    RAISE EXCEPTION 'Storage quota exceeded. % of % used.',
      pg_size_pretty(current_used),
      pg_size_pretty(max_bytes)
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_org_storage_limit_tr ON note_attachments;
CREATE TRIGGER enforce_org_storage_limit_tr
  BEFORE INSERT ON note_attachments
  FOR EACH ROW EXECUTE FUNCTION enforce_org_storage_limit();


-- ── Helper: quick-check seat availability without actually inserting.
-- Used by join.html to give a friendly "org is full" message BEFORE
-- the user clicks the accept button.
CREATE OR REPLACE FUNCTION org_seat_availability(org_uuid UUID)
RETURNS TABLE(seats_used INT, seats_allowed INT, available BOOLEAN, reason TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  max_seats  INT;
  used       INT;
  sub_status TEXT;
BEGIN
  SELECT o.seats_allowed, o.subscription_status
    INTO max_seats, sub_status
    FROM organizations o
    WHERE o.id = org_uuid;

  IF max_seats IS NULL THEN
    RETURN QUERY SELECT 0, 0, false, 'Organization not found';
    RETURN;
  END IF;

  SELECT COUNT(*) INTO used FROM org_members WHERE org_id = org_uuid;

  IF max_seats = 0 THEN
    RETURN QUERY SELECT used, 0, false, 'No active subscription';
    RETURN;
  END IF;

  IF sub_status IS NOT NULL AND sub_status NOT IN ('active', 'trialing') THEN
    RETURN QUERY SELECT used, max_seats, false, 'Subscription inactive (' || sub_status || ')';
    RETURN;
  END IF;

  IF used >= max_seats THEN
    RETURN QUERY SELECT used, max_seats, false, 'Seat limit reached';
    RETURN;
  END IF;

  RETURN QUERY SELECT used, max_seats, true, NULL::text;
END;
$$;
