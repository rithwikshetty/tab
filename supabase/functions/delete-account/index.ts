// delete-account: authenticated user requests permanent account deletion
// (App Store guideline 5.1.1(v)). Deployed with verify_jwt = true, so only a
// valid session reaches this code; the user is taken from the caller's own
// token — no client-supplied IDs are trusted.
//
// Order matters: purge ledger data first (returns receipt paths), then remove
// storage objects, then delete the auth user. The purge keeps an anonymized
// ghost profile so shared-trip ledger rows stay intact for other members.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return new Response("unauthorized", { status: 401 });
  }
  const userId = userData.user.id;

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: receiptRows, error: purgeError } = await admin.rpc(
    "delete_account_data",
    { p_user: userId },
  );
  if (purgeError) {
    console.error("delete_account_data failed", { userId, purgeError });
    return new Response("purge failed", { status: 500 });
  }

  const paths = (receiptRows ?? [])
    .map((row: { receipt_path: string | null }) => row.receipt_path)
    .filter((path: string | null): path is string => !!path);
  if (paths.length > 0) {
    // Best-effort: a leftover receipt object must not strand the deletion.
    const { error: storageError } = await admin.storage
      .from("receipts")
      .remove(paths);
    if (storageError) {
      console.error("receipt cleanup failed", { userId, storageError });
    }
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error("auth user deletion failed", { userId, deleteError });
    return new Response("auth deletion failed", { status: 500 });
  }

  return new Response(JSON.stringify({ deleted: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
