import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const jsonHeaders = (origin: string | null, allowedOrigins: Set<string>) => ({
  'Content-Type': 'application/json',
  ...(origin && allowedOrigins.has(origin) ? { 'Access-Control-Allow-Origin': origin, Vary: 'Origin' } : {}),
  'Access-Control-Allow-Headers': 'authorization, content-type, x-client-info, apikey',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
});

const reply = (body: Record<string, unknown>, status: number, origin: string | null, allowedOrigins: Set<string>) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders(origin, allowedOrigins) });

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

Deno.serve(async (request) => {
  const origin = request.headers.get('origin');
  const configuredOrigins = Deno.env.get('ALLOWED_ORIGINS');
  const allowedOrigins = new Set((configuredOrigins || '').split(',').map((value) => value.trim()).filter(Boolean));
  if (!configuredOrigins || allowedOrigins.size === 0) return reply({ error: 'Service unavailable.' }, 503, origin, allowedOrigins);
  if (origin && !allowedOrigins.has(origin)) return reply({ error: 'Origin not allowed.' }, 403, origin, allowedOrigins);
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: jsonHeaders(origin, allowedOrigins) });
  if (request.method !== 'POST') return reply({ error: 'Method not allowed.' }, 405, origin, allowedOrigins);

  const authorization = request.headers.get('authorization');
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  const body = await request.json().catch(() => null);
  if (!token || !body || typeof body !== 'object' || Array.isArray(body)) return reply({ error: 'Invalid request.' }, 400, origin, allowedOrigins);
  const { action, userId, ...extra } = body as Record<string, unknown>;
  if (action !== 'delete' || Object.keys(extra).length !== 0 || typeof userId !== 'string' || !uuid.test(userId)) {
    return reply({ error: 'Invalid request.' }, 400, origin, allowedOrigins);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceRole) return reply({ error: 'Service unavailable.' }, 503, origin, allowedOrigins);
  const admin = createClient(url, serviceRole, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user || !authData.user.email_confirmed_at) return reply({ error: 'Unauthorized.' }, 401, origin, allowedOrigins);
  if (authData.user.id === userId) return reply({ error: 'An administrator cannot delete their own account.' }, 403, origin, allowedOrigins);

  const [{ data: caller }, { data: target }, { data: activeAdministrators, error: administratorError }] = await Promise.all([
    admin.from('profiles').select('account_status').eq('id', authData.user.id).maybeSingle(),
    admin.from('profiles').select('id').eq('id', userId).maybeSingle(),
    admin.rpc('active_confirmed_administrator_count', { p_exclude_profile_id: userId }),
  ]);
  if (!caller || caller.account_status !== 'active') return reply({ error: 'Forbidden.' }, 403, origin, allowedOrigins);
  const { data: callerAdmin } = await admin.from('administrators').select('profile_id').eq('profile_id', authData.user.id).maybeSingle();
  if (!callerAdmin) return reply({ error: 'Forbidden.' }, 403, origin, allowedOrigins);
  if (!target) return reply({ error: 'User not found.' }, 404, origin, allowedOrigins);
  const { data: targetAdmin } = await admin.from('administrators').select('profile_id').eq('profile_id', userId).maybeSingle();
  if (administratorError) return reply({ error: 'Service unavailable.' }, 503, origin, allowedOrigins);
  if (targetAdmin && (activeAdministrators || 0) < 1) return reply({ error: 'Cannot delete the last active confirmed administrator.' }, 409, origin, allowedOrigins);

  // Qualsevol referència d'autoria, revisió o gestió és procedència: no la
  // convertim en NULL en eliminar un perfil, encara que la FK ho permeta.
  const provenanceChecks = [
    ['catalog_objects', 'created_by', 'catalog_objects.created_by'], ['catalog_objects', 'reviewed_by', 'catalog_objects.reviewed_by'],
    ['catalog_object_history', 'actor_id', 'catalog_object_history.actor_id'], ['catalog_object_revisions', 'changed_by', 'catalog_object_revisions.changed_by'],
    ['object_photos', 'uploaded_by', 'object_photos.uploaded_by'], ['tags', 'created_by', 'tags.created_by'], ['object_tags', 'created_by', 'object_tags.created_by'],
    ['change_proposals', 'submitted_by', 'change_proposals.submitted_by'], ['change_proposals', 'reviewed_by', 'change_proposals.reviewed_by'],
    ['activities', 'created_by', 'activities.created_by'], ['donation_contacts', 'handled_by', 'donation_contacts.handled_by'],
    ['video_proposals', 'submitted_by', 'video_proposals.submitted_by'], ['video_proposals', 'reviewed_by', 'video_proposals.reviewed_by'],
    ['historical_figures', 'created_by', 'historical_figures.created_by'], ['historical_figures', 'updated_by', 'historical_figures.updated_by'],
    ['profiles', 'approved_by', 'profiles.approved_by'], ['profiles', 'suspended_by', 'profiles.suspended_by'],
  ] as const;
  const checks = await Promise.all(provenanceChecks.map(async ([table, column, label]) => {
    const { count, error } = await admin.from(table).select('id', { count: 'exact', head: true }).eq(column, userId);
    return { label, count: count || 0, error };
  }));
  if (checks.some(({ error }) => error)) return reply({ error: 'Service unavailable.' }, 503, origin, allowedOrigins);
  const provenanceReferences = checks.filter(({ count }) => count > 0).map(({ label }) => label);
  if (provenanceReferences.length > 0) {
    return reply({ error: 'Account has authored or audit data and cannot be deleted without changing provenance.', references: provenanceReferences }, 409, origin, allowedOrigins);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId, false);
  if (deleteError) return reply({ error: 'Account deletion could not be completed.' }, 409, origin, allowedOrigins);
  return reply({ ok: true }, 200, origin, allowedOrigins);
});
