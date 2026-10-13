import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  CollezionePosseduta,
  Dipendenze,
  eliminaAccount,
} from "./elimina_account.ts";

/** Supabase e Apple in memoria; `passi` registra l'ordine delle chiamate. */
function finto(opzioni: {
  possedute?: CollezionePosseduta[];
  file?: Record<string, string[]>;
  appleFallisce?: boolean;
} = {}) {
  const passi: string[] = [];
  const file = structuredClone(opzioni.file ?? {});
  const deps: Dipendenze = {
    utente: (jwt) => Promise.resolve(jwt === "valido" ? "u1" : null),
    collezioniPossedute: () =>
      Promise.resolve(opzioni.possedute ?? [{ id: "c1", altriMembri: 0 }]),
    elencaFile: (bucket, cartella) =>
      Promise.resolve(
        (file[bucket] ?? []).filter((p) => p.startsWith(`${cartella}/`)),
      ),
    rimuoviFile: (bucket, percorsi) => {
      passi.push(`rimuovi ${bucket} ${percorsi.length}`);
      file[bucket] = file[bucket].filter((p) => !percorsi.includes(p));
      return Promise.resolve();
    },
    revocaApple: (code) => {
      passi.push(`revoca ${code}`);
      return opzioni.appleFallisce
        ? Promise.reject(new Error("invalid_grant"))
        : Promise.resolve();
    },
    eliminaUtente: (id) => {
      passi.push(`elimina ${id}`);
      return Promise.resolve();
    },
  };
  return { deps, passi, file };
}

Deno.test("senza JWT valido non tocca nulla", async () => {
  const { deps, passi } = finto();

  assertEquals(await eliminaAccount(deps, { jwt: null }), {
    ok: false,
    status: 401,
    errore: "non_autenticato",
  });
  assertEquals(await eliminaAccount(deps, { jwt: "scaduto" }), {
    ok: false,
    status: 401,
    errore: "non_autenticato",
  });
  assertEquals(passi, []);
});

Deno.test(
  "Proprietario senza collaboratori: cancella cover e scansioni, poi l'utente",
  async () => {
    const { deps, passi, file } = finto({
      file: {
        covers: ["c1/a.jpg", "c1/b.jpg", "altra/x.jpg"],
        scansioni: ["u1/s.jpg", "u2/t.jpg"],
      },
    });

    assertEquals(await eliminaAccount(deps, { jwt: "valido" }), { ok: true });
    assertEquals(file, { covers: ["altra/x.jpg"], scansioni: ["u2/t.jpg"] });
    assertEquals(passi.at(-1), "elimina u1");
  },
);

Deno.test("Proprietario con collaboratori: rifiuta prima di cancellare i file", async () => {
  const { deps, passi } = finto({
    possedute: [{ id: "c1", altriMembri: 2 }],
    file: { covers: ["c1/a.jpg"] },
  });

  assertEquals(await eliminaAccount(deps, { jwt: "valido" }), {
    ok: false,
    status: 409,
    errore: "proprietario_con_collaboratori",
  });
  assertEquals(passi, []);
});

Deno.test("con il code Apple revoca il token prima di cancellare", async () => {
  const { deps, passi } = finto({ file: { covers: ["c1/a.jpg"] } });

  await eliminaAccount(deps, {
    jwt: "valido",
    appleAuthorizationCode: "code",
  });

  assertEquals(passi, ["revoca code", "rimuovi covers 1", "elimina u1"]);
});

Deno.test("se la revoca Apple fallisce l'account resta intatto", async () => {
  const { deps, passi } = finto({
    appleFallisce: true,
    file: { covers: ["c1/a.jpg"] },
  });

  assertEquals(
    await eliminaAccount(deps, {
      jwt: "valido",
      appleAuthorizationCode: "code",
    }),
    { ok: false, status: 502, errore: "revoca_apple_fallita" },
  );
  assertEquals(passi, ["revoca code"]);
});

Deno.test("rimuove i file a lotti di 1000", async () => {
  const { deps, passi } = finto({
    file: {
      scansioni: Array.from({ length: 2500 }, (_, i) => `u1/${i}.jpg`),
    },
  });

  await eliminaAccount(deps, { jwt: "valido" });

  assertEquals(passi, [
    "rimuovi scansioni 1000",
    "rimuovi scansioni 1000",
    "rimuovi scansioni 500",
    "elimina u1",
  ]);
});
