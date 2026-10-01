import { createClient } from 'npm:@supabase/supabase-js@2.117.2';

const origin = 'https://mharb11223344.github.io';
const headers = {
  'Access-Control-Allow-Origin': origin,
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Content-Type': 'application/json',
};
const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers });
const url = Deno.env.get('SUPABASE_URL')!;
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const result = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(result), b => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async request => {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return respond(405, { error: 'Method not allowed' });
  if (request.headers.get('origin') !== origin) return respond(403, { error: 'Origin not allowed' });
  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return respond(400, { error: 'Invalid request' }); }
  const action = String(body.action || '');

  if (action === 'activate') {
    const email = String(body.email || '').trim().toLowerCase();
    const code = String(body.code || '').trim().toUpperCase();
    const password = String(body.password || '');
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !/^[A-Z0-9]{12}$/.test(code) || password.length < 8 || password.length > 128)
      return respond(400, { error: 'Enter a valid email, activation code, and password of at least 8 characters.' });
    const { data: row, error: readError } = await admin.from('teacher_activation')
      .select('user_id,email,code_hash,expires_at,attempts,used_at').eq('email', email).maybeSingle();
    if (readError) return respond(500, { error: 'Activation is temporarily unavailable.' });
    if (!row || row.used_at || row.attempts >= 5 || new Date(row.expires_at).getTime() < Date.now())
      return respond(400, { error: 'The activation code is invalid or expired. Contact the portal owner.' });
    const hash = await sha256(code);
    if (hash !== row.code_hash) {
      await admin.from('teacher_activation').update({ attempts: row.attempts + 1 }).eq('user_id', row.user_id).is('used_at', null);
      return respond(400, { error: 'The activation code is invalid or expired. Contact the portal owner.' });
    }
    const { data: claimed, error: claimError } = await admin.from('teacher_activation')
      .update({ used_at: new Date().toISOString() }).eq('user_id', row.user_id)
      .eq('code_hash', hash).is('used_at', null).select('user_id').maybeSingle();
    if (claimError || !claimed) return respond(409, { error: 'This activation code has already been used.' });
    const { data: authUser, error: lookupError } = await admin.auth.admin.getUserById(row.user_id);
    if (lookupError || authUser.user?.email?.toLowerCase() !== email) return respond(400, { error: 'The teacher account could not be verified.' });
    const { error: passwordError } = await admin.auth.admin.updateUserById(row.user_id, { password });
    if (passwordError) {
      await admin.from('teacher_activation').update({ used_at: null }).eq('user_id', row.user_id);
      return respond(500, { error: 'Could not set the password. Please try again.' });
    }
    const { error: roleError } = await admin.from('teacher_admins').insert({ user_id: row.user_id });
    if (roleError && roleError.code !== '23505') return respond(500, { error: 'Could not enable the teacher dashboard. Contact the portal owner.' });
    return respond(200, { ok: true });
  }

  const token = request.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!token) return respond(401, { error: 'Sign in required' });
  const { data: auth, error: authError } = await admin.auth.getUser(token);
  if (authError || !auth.user) return respond(401, { error: 'Sign in required' });
  const { data: teacher } = await admin.from('teacher_admins').select('user_id').eq('user_id', auth.user.id).maybeSingle();
  if (!teacher) return respond(403, { error: 'Teacher permission required' });
  const userId = String(body.userId || '');
  if (!/^[0-9a-f-]{36}$/i.test(userId) || userId === auth.user.id) return respond(400, { error: 'Invalid student account' });
  const { data: student } = await admin.from('student_profiles').select('user_id').eq('user_id', userId).maybeSingle();
  const { data: targetTeacher } = await admin.from('teacher_admins').select('user_id').eq('user_id', userId).maybeSingle();
  if (!student || targetTeacher) return respond(400, { error: 'Student account not found' });
  if (action === 'password') {
    const password = String(body.password || '');
    if (password.length < 8 || password.length > 128) return respond(400, { error: 'Use a password from 8 to 128 characters.' });
    const { error } = await admin.auth.admin.updateUserById(userId, { password });
    return error ? respond(500, { error: 'Could not update the password.' }) : respond(200, { ok: true });
  }
  if (action === 'delete') {
    const { error } = await admin.auth.admin.deleteUser(userId);
    return error ? respond(500, { error: 'Could not delete the account.' }) : respond(200, { ok: true });
  }
  return respond(400, { error: 'Unknown action' });
});
