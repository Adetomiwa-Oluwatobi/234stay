// ============================================
// 234Stays — Supabase config
// Fill in your own project values below.
// Find them in: Supabase Dashboard → Project Settings → API
// ============================================
const SUPABASE_URL = 'https://ybqjnmwasfpezjrhuviq.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_Uh5PqJlM4_5Hw2cnh2HyqA_eqWo3lCe';

const supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
