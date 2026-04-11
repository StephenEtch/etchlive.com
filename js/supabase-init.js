// js/supabase-init.js — Supabase client for Etch website
// Loaded AFTER the Supabase CDN script in each HTML page.

const SUPABASE_URL  = 'https://jcsmeyprhxveekwgzkto.supabase.co';
const SUPABASE_ANON = 'sb_publishable_s5D0dQpnsg5xmMvDRCLIcg_9RSVr5BC';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON);

// ── Helpers ──────────────────────────────────────────────────────────────────

async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

async function getUser() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

async function getProfile(userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();
  if (error) { console.error('[getProfile]', error.message); return null; }
  return data;
}

async function signOut() {
  await supabase.auth.signOut();
  window.location.href = '/';
}

// ── Nav auth state ───────────────────────────────────────────────────────────
// Call this on any page that has a nav with [data-auth-link] elements.

async function updateNavAuth() {
  const link = document.querySelector('[data-auth-link]');
  if (!link) return;
  const session = await getSession();
  if (session) {
    link.textContent = 'Dashboard';
    link.href = '/dashboard.html';
  } else {
    link.textContent = 'Login';
    link.href = '/login.html';
  }
}
