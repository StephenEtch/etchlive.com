-- ═══════════════════════════════════════════════════════════════════
-- Etch — Supabase Setup for Website Auth
-- ═══════════════════════════════════════════════════════════════════
-- Run this in Supabase Dashboard → SQL Editor if these objects
-- don't already exist. The Electron app may have created them already.
--
-- IMPORTANT: Also enable in Supabase Dashboard:
--   Authentication → Providers → Email:
--     ✓ Enable Email provider
--     ✓ Enable email+password sign-in (not just magic link)
--   Authentication → URL Configuration:
--     Site URL: https://etchlive.com
--     Redirect URLs: https://etchlive.com/account.html
-- ═══════════════════════════════════════════════════════════════════

-- ── Profiles table ───────────────────────────────────────────────
-- Stores user profile data linked to Supabase auth.users.
-- The Electron app already creates this with: name, default_role, avatar_color.
-- The website also writes: name, default_role, avatar_color, email.

CREATE TABLE IF NOT EXISTS profiles (
  id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  name         TEXT,
  email        TEXT,
  default_role TEXT DEFAULT 'gen',
  avatar_color TEXT DEFAULT '#e05a2b',
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now()
);

-- ── Auto-create profile on signup ────────────────────────────────
-- Triggers when a new user signs up (email+password or anonymous).

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop existing trigger if it exists, then recreate
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── Row Level Security ───────────────────────────────────────────
-- Users can only read and update their own profile.

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  -- Select own profile
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can view own profile'
  ) THEN
    CREATE POLICY "Users can view own profile"
      ON profiles FOR SELECT USING (auth.uid() = id);
  END IF;

  -- Update own profile
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can update own profile'
  ) THEN
    CREATE POLICY "Users can update own profile"
      ON profiles FOR UPDATE USING (auth.uid() = id);
  END IF;

  -- Insert own profile (for upsert from website signup)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can insert own profile'
  ) THEN
    CREATE POLICY "Users can insert own profile"
      ON profiles FOR INSERT WITH CHECK (auth.uid() = id);
  END IF;

  -- Delete own profile (for account deletion)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'profiles' AND policyname = 'Users can delete own profile'
  ) THEN
    CREATE POLICY "Users can delete own profile"
      ON profiles FOR DELETE USING (auth.uid() = id);
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════
-- The following tables should already exist from the Electron app
-- setup. Listed here for reference only — do NOT re-run if they
-- already exist.
-- ═══════════════════════════════════════════════════════════════════
--
-- organizations     — team/company groupings
-- org_members        — user ↔ organization membership (role: owner/admin/member)
-- projects           — shows within an organization
-- sessions           — rehearsal/show sessions within a project
-- session_members    — user ↔ session membership
-- notes              — timestamped production notes
-- songs              — setlist tracks per session
-- user_session_state — per-user UI state (zoom, filters, theme)
