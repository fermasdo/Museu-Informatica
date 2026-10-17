import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const url = import.meta.env.PUBLIC_SUPABASE_URL;
const key = import.meta.env.PUBLIC_SUPABASE_KEY;

/** Null when the public catalogue backend has not yet been configured. */
export const supabase: SupabaseClient | null =
  url && key ? createClient(url, key) : null;
