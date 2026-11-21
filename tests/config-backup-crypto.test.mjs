import assert from "node:assert/strict";
import { test } from "node:test";
import { gzipSync } from "node:zlib";
import {
  decryptRouterConfigBackupBytes,
  encryptRouterConfigBackupBytes,
} from "../ui/quantumgrid/src/routerApi.ts";

const passphrase = "violet-river-quantum-grid-2026";
const gzipArchive = (value) => new Uint8Array(gzipSync(value));

test("encrypted backup container round-trips with authenticated AES-GCM encryption", async () => {
  const plaintext = gzipArchive("QGOS test archive\0private configuration payload");
  const encrypted = await encryptRouterConfigBackupBytes(plaintext, passphrase);
  assert.equal(new TextDecoder().decode(encrypted.slice(0, 8)), "QGOSBK01");
  assert.equal(encrypted.byteLength, plaintext.byteLength + 40 + 16);
  assert.notDeepEqual(encrypted.slice(40), plaintext);

  const decrypted = await decryptRouterConfigBackupBytes(encrypted, passphrase);
  assert.deepEqual(decrypted, plaintext);
});

test("each backup receives a fresh salt and nonce", async () => {
  const plaintext = gzipArchive("same configuration archive");
  const first = await encryptRouterConfigBackupBytes(plaintext, passphrase);
  const second = await encryptRouterConfigBackupBytes(plaintext, passphrase);
  assert.notDeepEqual(first.slice(12, 40), second.slice(12, 40));
  assert.notDeepEqual(first, second);
});

test("wrong passphrases and modified ciphertext fail authenticated decryption", async () => {
  const encrypted = await encryptRouterConfigBackupBytes(
    gzipArchive("sensitive router configuration"),
    passphrase,
  );
  await assert.rejects(
    decryptRouterConfigBackupBytes(encrypted, "incorrect passphrase for backup"),
    /passphrase is incorrect or the encrypted backup has been modified/,
  );

  const modified = encrypted.slice();
  modified[modified.length - 1] ^= 0x01;
  await assert.rejects(
    decryptRouterConfigBackupBytes(modified, passphrase),
    /passphrase is incorrect or the encrypted backup has been modified/,
  );
});

test("header metadata is authenticated and unsafe KDF settings are rejected", async () => {
  const encrypted = await encryptRouterConfigBackupBytes(
    gzipArchive("private configuration"),
    passphrase,
  );

  const changedSalt = encrypted.slice();
  changedSalt[12] ^= 0x80;
  await assert.rejects(
    decryptRouterConfigBackupBytes(changedSalt, passphrase),
    /passphrase is incorrect or the encrypted backup has been modified/,
  );

  const downgraded = encrypted.slice();
  new DataView(downgraded.buffer).setUint32(8, 1, false);
  await assert.rejects(
    decryptRouterConfigBackupBytes(downgraded, passphrase),
    /unsupported or unsafe key-derivation setting/,
  );
});

test("backup encryption rejects short passphrases, oversized secrets and invalid containers", async () => {
  const plaintext = gzipArchive("config");
  await assert.rejects(
    encryptRouterConfigBackupBytes(plaintext, "too short"),
    /at least 16 characters/,
  );
  await assert.rejects(
    encryptRouterConfigBackupBytes(new TextEncoder().encode("not gzip"), passphrase),
    /not a valid gzip configuration archive/,
  );
  await assert.rejects(
    decryptRouterConfigBackupBytes(new Uint8Array(56), passphrase),
    /empty, truncated or larger/,
  );
  await assert.rejects(
    decryptRouterConfigBackupBytes(new Uint8Array(57), passphrase),
    /supported QuantumGrid encrypted backup/,
  );
  await assert.rejects(
    decryptRouterConfigBackupBytes(new Uint8Array(10), passphrase),
    /empty, truncated or larger/,
  );
});

