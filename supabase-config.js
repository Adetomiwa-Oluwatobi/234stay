// ============================================
// 234Stays — Supabase config
// Replace with your project values from:
// Supabase Dashboard → Project Settings → API
// ============================================
const SUPABASE_URL = 'https://ybqjnmwasfpezjrhuviq.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_Uh5PqJlM4_5Hw2cnh2HyqA_eqWo3lCe';

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true
  }
});

// ── Auth helpers used across all pages ──────────────────

async function getSession() {
  const { data } = await supabaseClient.auth.getSession();
  return data.session;
}

async function getMyProfile() {
  const { data } = await supabaseClient.rpc('get_my_profile');
  return data ? JSON.parse(data) : null;
}

async function requireAuth(allowedRoles = ['admin', 'agency']) {
  const session = await getSession();
  if (!session) { window.location.href = 'login.html'; return null; }
  const profile = await getMyProfile();
  if (!profile || !allowedRoles.includes(profile.role)) {
    window.location.href = 'login.html';
    return null;
  }
  return { session, profile };
}

async function signOut() {
  await supabaseClient.auth.signOut();
  window.location.href = 'login.html';
}
