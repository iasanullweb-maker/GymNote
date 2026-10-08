import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";

// Administrative credentials are read only inside this function, never compiled into the app.
Deno.serve(async (request: Request) => {
  const headers = { "Content-Type": "application/json", "Cache-Control": "no-store" };
  const reply = (status: number) => new Response(JSON.stringify({ ok: status === 200 }), { status, headers });
  if (request.method !== "POST") return reply(405);
  const authorization = request.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return reply(401);
  const token = authorization.slice(7);
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return reply(503);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  try {
    // getUser verifies the token with Auth. Decode claims only AFTER successful server verification.
    const { data: { user }, error } = await admin.auth.getUser(token);
    if (error || !user) return reply(401);
    const encoded = token.split(".")[1];
    const claims = JSON.parse(atob(encoded.replace(/-/g, "+").replace(/_/g, "/")));
    const now = Math.floor(Date.now() / 1000);
    if (claims.sub !== user.id || typeof claims.session_id !== "string") return reply(401);
    // A refreshed JWT's iat is NOT proof of recent authentication. Require a recent interactive login in
    // this session's AMR: an email OTP or a provider (Google/Apple) OAuth sign-in, at most 5 minutes old.
    // token_refresh, password and other methods never count.
    const REAUTH_METHODS = ["otp", "oauth"];
    const recentLogin = Array.isArray(claims.amr) && claims.amr.some((entry: { method?: string; timestamp?: number }) =>
      typeof entry.method === "string" && REAUTH_METHODS.includes(entry.method) && typeof entry.timestamp === "number"
      && now - entry.timestamp >= 0 && now - entry.timestamp <= 300);
    if (!recentLogin) return reply(403);
    const scoped = createClient(url, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: active, error: sessionError } = await scoped.rpc("gymnote_session_valid");
    if (sessionError || active !== true) return reply(401);
    const { error: deletionError } = await admin.auth.admin.deleteUser(user.id);
    // workout_backups is removed by ON DELETE CASCADE; tokens and local copies are cleared by the app.
    return reply(deletionError ? 500 : 200);
  } catch { return reply(401); }
});
