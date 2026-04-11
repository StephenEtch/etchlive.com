// js/auth-guard.js — Redirect to login if not authenticated.
// Include on any protected page AFTER supabase-init.js.

(async function authGuard() {
  const session = await getSession();
  if (!session) {
    const redirect = encodeURIComponent(window.location.pathname);
    window.location.href = '/login.html?redirect=' + redirect;
  }
})();
