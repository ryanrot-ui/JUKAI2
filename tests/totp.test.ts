import { describe, expect, it } from "vitest";
import { generateTotpSecret, totpUri, verifyTotp } from "@/lib/totp";
import { createHmac } from "crypto";

// Reference HOTP implementation to cross-check codes for the test secret
function referenceCode(secretB32: string, timeMs: number): string {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let bits = 0;
  let value = 0;
  const bytes: number[] = [];
  for (const ch of secretB32) {
    value = (value << 5) | alphabet.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      bytes.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  const counter = Math.floor(timeMs / 1000 / 30);
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", Buffer.from(bytes)).update(buf).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const code =
    ((digest[offset] & 0x7f) << 24) |
    (digest[offset + 1] << 16) |
    (digest[offset + 2] << 8) |
    digest[offset + 3];
  return (code % 1_000_000).toString().padStart(6, "0");
}

describe("TOTP 2FA", () => {
  it("generates a base32 secret of sufficient entropy", () => {
    const secret = generateTotpSecret();
    expect(secret.length).toBeGreaterThanOrEqual(32); // 160 bits
    expect(/^[A-Z2-7]+$/.test(secret)).toBe(true);
    expect(generateTotpSecret()).not.toBe(secret);
  });

  it("accepts the current valid code and rejects wrong codes", () => {
    const secret = generateTotpSecret();
    const now = Date.now();
    const valid = referenceCode(secret, now);
    expect(verifyTotp(secret, valid, now)).toBe(true);
    const wrong = valid === "000000" ? "000001" : "000000";
    expect(verifyTotp(secret, wrong, now)).toBe(false);
  });

  it("tolerates ±1 time step of clock drift but not more", () => {
    const secret = generateTotpSecret();
    const now = 1_760_000_000_000;
    expect(verifyTotp(secret, referenceCode(secret, now - 30_000), now)).toBe(true);
    expect(verifyTotp(secret, referenceCode(secret, now + 30_000), now)).toBe(true);
    expect(verifyTotp(secret, referenceCode(secret, now - 90_000), now)).toBe(false);
  });

  it("rejects malformed codes without throwing", () => {
    const secret = generateTotpSecret();
    for (const bad of ["", "abc", "12345", "1234567", "12 34 5"]) {
      expect(verifyTotp(secret, bad)).toBe(false);
    }
  });

  it("produces a standard otpauth URI", () => {
    const uri = totpUri("ABCDEFGH", "admin@example.com");
    expect(uri).toMatch(/^otpauth:\/\/totp\/PumpTrader%3Aadmin%40example.com\?secret=ABCDEFGH/);
  });
});
