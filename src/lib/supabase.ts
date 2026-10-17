import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

/** Non-null when the build was produced without the two public Supabase settings. The app then shows a
 *  configuration error instead of pretending to be connected. */
export const configError: string | null =
  !url || !key ? 'This build is missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY.' : null;

// Only the public/publishable key is ever used in the browser. RLS and RPC authorization protect the data.
export const supabase = createClient(url ?? 'http://config-missing.invalid', key ?? 'config-missing', {
  auth: { flowType: 'pkce', persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});
