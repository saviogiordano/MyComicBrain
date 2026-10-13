// Edge Function `elimina-account` (#172): vedi `elimina_account.ts`.
//
// POST con il JWT dell'utente in `Authorization` e, per Apple su iOS,
// `{ "appleAuthorizationCode": "..." }`. Risponde 204 se l'account è
// eliminato, altrimenti `{ "errore": "<codice>" }` con lo status di
// `Esito`.
//
// Secret richiesti (`supabase secrets set`): APPLE_TEAM_ID, APPLE_KEY_ID,
// APPLE_PRIVATE_KEY, APPLE_CLIENT_ID. SUPABASE_URL e
// SUPABASE_SERVICE_ROLE_KEY sono forniti dalla piattaforma.

import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { revocaApple } from "./apple.ts";
import { Dipendenze, eliminaAccount } from "./elimina_account.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { autoRefreshToken: false, persistSession: false } },
);

const pagina = 1000;

const dipendenze: Dipendenze = {
  async utente(jwt) {
    const { data, error } = await admin.auth.getUser(jwt);
    return error ? null : data.user.id;
  },

  async collezioniPossedute(userId) {
    const { data: possedute, error } = await admin
      .from("collection_members")
      .select("collection_id")
      .eq("user_id", userId)
      .eq("role", "owner");
    if (error) throw error;
    const ids = possedute.map((r) => r.collection_id as string);
    if (ids.length === 0) return [];
    const { data: altri, error: erroreAltri } = await admin
      .from("collection_members")
      .select("collection_id")
      .in("collection_id", ids)
      .neq("user_id", userId);
    if (erroreAltri) throw erroreAltri;
    return ids.map((id) => ({
      id,
      altriMembri: altri.filter((r) => r.collection_id === id).length,
    }));
  },

  async elencaFile(bucket, cartella) {
    const percorsi: string[] = [];
    for (let offset = 0;; offset += pagina) {
      const { data, error } = await admin.storage
        .from(bucket)
        .list(cartella, { limit: pagina, offset });
      if (error) throw error;
      percorsi.push(...data.map((f) => `${cartella}/${f.name}`));
      if (data.length < pagina) return percorsi;
    }
  },

  async rimuoviFile(bucket, percorsi) {
    const { error } = await admin.storage.from(bucket).remove(percorsi);
    if (error) throw error;
  },

  revocaApple(code) {
    const nomi = [
      "APPLE_TEAM_ID",
      "APPLE_KEY_ID",
      "APPLE_PRIVATE_KEY",
      "APPLE_CLIENT_ID",
    ];
    const mancanti = nomi.filter((nome) => !Deno.env.get(nome));
    if (mancanti.length > 0) {
      throw new Error(`secret mancanti: ${mancanti.join(", ")}`);
    }
    return revocaApple({
      teamId: Deno.env.get("APPLE_TEAM_ID")!,
      keyId: Deno.env.get("APPLE_KEY_ID")!,
      privateKey: Deno.env.get("APPLE_PRIVATE_KEY")!,
      clientId: Deno.env.get("APPLE_CLIENT_ID")!,
    }, code);
  },

  async eliminaUtente(userId) {
    const { error } = await admin.auth.admin.deleteUser(userId);
    if (error) throw error;
  },
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });

  const jwt = req.headers.get("Authorization")?.replace(/^Bearer /, "") ??
    null;
  const corpo = await req.json().catch(() => ({}));

  try {
    const esito = await eliminaAccount(dipendenze, {
      jwt,
      appleAuthorizationCode: typeof corpo.appleAuthorizationCode === "string"
        ? corpo.appleAuthorizationCode
        : undefined,
    });
    if (esito.ok) return new Response(null, { status: 204 });
    return Response.json({ errore: esito.errore }, { status: esito.status });
  } catch (e) {
    console.error("eliminazione account fallita", e);
    return Response.json({ errore: "sconosciuto" }, { status: 500 });
  }
});
