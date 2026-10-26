import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });

  const body = await request.json().catch(() => null) as Record<string, unknown> | null;
  const name = typeof body?.name === 'string' ? body.name.trim() : '';
  const email = typeof body?.email === 'string' ? body.email.trim() : '';
  const phone = typeof body?.phone === 'string' ? body.phone.trim() : '';
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  const token = typeof body?.turnstileToken === 'string' ? body.turnstileToken : '';
  if (name.length < 2 || name.length > 120 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || message.length < 10 || message.length > 3000 || !token) {
    return Response.json({ error: 'Dades de contacte no vàlides.' }, { status: 400, headers: cors });
  }

  const secret = Deno.env.get('TURNSTILE_SECRET_KEY');
  if (!secret) return Response.json({ error: 'La protecció del formulari no està configurada.' }, { status: 503, headers: cors });
  const verification = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ secret, response: token, remoteip: request.headers.get('x-forwarded-for')?.split(',')[0] || '' }),
  }).then(response => response.json() as Promise<{ success: boolean }>).catch(() => ({ success: false }));
  if (!verification.success) return Response.json({ error: 'No s’ha pogut validar la protecció antiabús.' }, { status: 400, headers: cors });

  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { error } = await client.from('donation_contacts').insert({ name, email, phone: phone || null, message, consent_at: new Date().toISOString(), consent_version: '2026-10' });
  if (error) return Response.json({ error: 'No s’ha pogut desar la proposta.' }, { status: 500, headers: cors });
  return Response.json({ ok: true }, { headers: cors });
});
