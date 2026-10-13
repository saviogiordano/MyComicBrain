// Cancellazione dell'account dall'app (App Store 5.1.1(v), #172).
//
// Il grosso lo fa il DB: alla cancellazione di `auth.users` il trigger
// `private.handle_deleted_user` (ADR-0004) blocca il Proprietario con
// collaboratori, elimina le Collezioni di cui l'utente è l'unico membro e
// anonimizza il Profilo. Restano fuori dal DB:
// - i file Storage (`covers/<collection_id>/*`, `scansioni/<user_id>/*`),
//   che SQL non può cancellare;
// - la revoca del token Sign in with Apple, richiesta da Apple a chi offre
//   il login con Apple.
//
// L'ordine è scelto perché un fallimento lasci l'account intatto e
// riprovabile: prima i controlli e la revoca, poi i file, per ultimo
// l'utente.

export interface CollezionePosseduta {
  id: string;
  altriMembri: number;
}

export interface Dipendenze {
  /** L'id dell'utente del JWT, `null` se il token non è valido. */
  utente(jwt: string): Promise<string | null>;
  collezioniPossedute(userId: string): Promise<CollezionePosseduta[]>;
  /** Percorsi completi (`<cartella>/<file>`) dei file nella cartella. */
  elencaFile(bucket: string, cartella: string): Promise<string[]>;
  rimuoviFile(bucket: string, percorsi: string[]): Promise<void>;
  /** Scambia l'authorization code con Apple e revoca il refresh token. */
  revocaApple(authorizationCode: string): Promise<void>;
  eliminaUtente(userId: string): Promise<void>;
}

export interface Richiesta {
  jwt: string | null;
  /** Code fresco del foglio Apple (iOS); assente per gli altri provider. */
  appleAuthorizationCode?: string;
}

export type Errore =
  | "non_autenticato"
  | "proprietario_con_collaboratori"
  | "revoca_apple_fallita"
  | "sconosciuto";

export type Esito = { ok: true } | {
  ok: false;
  status: number;
  errore: Errore;
};

// Limite di `remove` dello Storage API per singola chiamata.
const lottoRimozione = 1000;

export async function eliminaAccount(
  deps: Dipendenze,
  richiesta: Richiesta,
): Promise<Esito> {
  const userId = richiesta.jwt ? await deps.utente(richiesta.jwt) : null;
  if (!userId) return { ok: false, status: 401, errore: "non_autenticato" };

  const possedute = await deps.collezioniPossedute(userId);
  // Stesso controllo del trigger, anticipato: senza, i file verrebbero
  // cancellati prima che il DB rifiuti l'eliminazione.
  if (possedute.some((c) => c.altriMembri > 0)) {
    return { ok: false, status: 409, errore: "proprietario_con_collaboratori" };
  }

  if (richiesta.appleAuthorizationCode) {
    try {
      await deps.revocaApple(richiesta.appleAuthorizationCode);
    } catch (e) {
      console.error("revoca Apple fallita", e);
      return { ok: false, status: 502, errore: "revoca_apple_fallita" };
    }
  }

  const cartelle: [string, string][] = [
    ...possedute.map((c): [string, string] => ["covers", c.id]),
    ["scansioni", userId],
  ];
  for (const [bucket, cartella] of cartelle) {
    const percorsi = await deps.elencaFile(bucket, cartella);
    for (let i = 0; i < percorsi.length; i += lottoRimozione) {
      await deps.rimuoviFile(bucket, percorsi.slice(i, i + lottoRimozione));
    }
  }

  await deps.eliminaUtente(userId);
  return { ok: true };
}
