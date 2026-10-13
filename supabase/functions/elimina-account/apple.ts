// Revoca del token Sign in with Apple
// (https://developer.apple.com/documentation/sign_in_with_apple/revoke_tokens).
// L'app manda un authorization code fresco del foglio Apple nativo: lo si
// scambia per un refresh token e lo si revoca. Il code nativo è emesso per
// il bundle id, quindi `clientId` è il bundle id, non il Services ID.

import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

export interface ConfigApple {
  teamId: string;
  keyId: string;
  /** Contenuto del file `.p8` (PKCS#8 PEM). */
  privateKey: string;
  clientId: string;
}

const appleId = "https://appleid.apple.com";

/**
 * Ricostruisce il PEM PKCS#8 dal solo corpo base64: un `.p8` passato a
 * `supabase secrets set` può perdere gli a capo, averli come `\n`
 * letterali o portarsi dietro virgolette e spazi, e `jose` rifiuta tutto
 * ciò che non inizia esattamente con l'intestazione.
 */
export function pemPkcs8(valore: string): string {
  const corpo = valore
    .replace(/-----(BEGIN|END) PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/[^A-Za-z0-9+/=]/g, "");
  const righe = corpo.match(/.{1,64}/g) ?? [];
  return [
    "-----BEGIN PRIVATE KEY-----",
    ...righe,
    "-----END PRIVATE KEY-----",
  ].join("\n");
}

async function clientSecret(config: ConfigApple): Promise<string> {
  const chiave = await importPKCS8(pemPkcs8(config.privateKey), "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: config.keyId })
    .setIssuer(config.teamId)
    .setSubject(config.clientId)
    .setAudience(appleId)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(chiave);
}

async function post(
  percorso: string,
  campi: Record<string, string>,
): Promise<Response> {
  const risposta = await fetch(`${appleId}${percorso}`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(campi),
  });
  if (!risposta.ok) {
    throw new Error(`${percorso}: ${risposta.status} ${await risposta.text()}`);
  }
  return risposta;
}

export async function revocaApple(
  config: ConfigApple,
  authorizationCode: string,
): Promise<void> {
  const secret = await clientSecret(config);
  const token = await post("/auth/token", {
    client_id: config.clientId,
    client_secret: secret,
    code: authorizationCode,
    grant_type: "authorization_code",
  });
  const { refresh_token: refreshToken } = await token.json();
  await post("/auth/revoke", {
    client_id: config.clientId,
    client_secret: secret,
    token: refreshToken,
    token_type_hint: "refresh_token",
  });
}
