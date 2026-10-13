import { assertEquals } from "jsr:@std/assert@1.0.14";
import { importPKCS8 } from "npm:jose@5.9.6";
import { pemPkcs8 } from "./apple.ts";

// Chiave ES256 di prova generata al volo, mai una chiave reale.
async function pemDiProva(): Promise<string> {
  const { privateKey } = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", privateKey),
  );
  const corpo = btoa(String.fromCharCode(...der)).match(/.{1,64}/g)!;
  return [
    "-----BEGIN PRIVATE KEY-----",
    ...corpo,
    "-----END PRIVATE KEY-----",
  ].join("\n");
}

Deno.test("pemPkcs8 accetta il .p8 comunque sia arrivato nel secret", async () => {
  const pem = await pemDiProva();
  const varianti = [
    pem,
    `${pem}\n`,
    pem.replaceAll("\n", "\r\n"),
    pem.replaceAll("\n", "\\n"),
    pem.replaceAll("\n", " "),
    pem.replaceAll("\n", ""),
    `"${pem}"`,
    `  ${pem}`,
  ];
  for (const variante of varianti) {
    assertEquals(pemPkcs8(variante), pem);
    await importPKCS8(pemPkcs8(variante), "ES256");
  }
});
