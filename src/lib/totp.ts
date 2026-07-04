import { createHmac, randomBytes, timingSafeEqual } from "crypto";

/**
 * RFC 6238 TOTP (SHA-1, 6 digits, 30s period) — dependency-free so the whole
 * 2FA path is auditable in one file. Compatible with Google Authenticator,
 * Authy, 1Password, etc.
 */

const B32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const PERIOD_S = 30;
const DIGITS = 6;

export function generateTotpSecret(): string {
  const bytes = randomBytes(20);
  let bits = 0;
  let value = 0;
  let out = "";
  for (const byte of bytes) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32_ALPHABET[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32_ALPHABET[(value << (5 - bits)) & 31];
  return out;
}

function base32Decode(secret: string): Buffer {
  const clean = secret.toUpperCase().replace(/[^A-Z2-7]/g, "");
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of clean) {
    value = (value << 5) | B32_ALPHABET.indexOf(ch);
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

function hotp(secret: Buffer, counter: number): string {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64BE(BigInt(counter));
  const digest = createHmac("sha1", secret).update(buf).digest();
  const offset = digest[digest.length - 1] & 0x0f;
  const code =
    ((digest[offset] & 0x7f) << 24) |
    (digest[offset + 1] << 16) |
    (digest[offset + 2] << 8) |
    digest[offset + 3];
  return (code % 10 ** DIGITS).toString().padStart(DIGITS, "0");
}

/** Verify a 6-digit code, accepting ±1 time step of clock drift. */
export function verifyTotp(secret: string, code: string, now = Date.now()): boolean {
  const cleaned = code.replace(/\s/g, "");
  if (!/^\d{6}$/.test(cleaned)) return false;
  const key = base32Decode(secret);
  if (key.length === 0) return false;
  const counter = Math.floor(now / 1000 / PERIOD_S);
  for (const drift of [0, -1, 1]) {
    const expected = hotp(key, counter + drift);
    if (
      expected.length === cleaned.length &&
      timingSafeEqual(Buffer.from(expected), Buffer.from(cleaned))
    ) {
      return true;
    }
  }
  return false;
}

/** otpauth:// URI for authenticator apps (renderable as a QR code). */
export function totpUri(secret: string, email: string, issuer = "PumpTrader"): string {
  const label = encodeURIComponent(`${issuer}:${email}`);
  return `otpauth://totp/${label}?secret=${secret}&issuer=${encodeURIComponent(issuer)}&algorithm=SHA1&digits=${DIGITS}&period=${PERIOD_S}`;
}
