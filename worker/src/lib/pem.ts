// PKCS#8 PEM → DER, for `crypto.subtle.importKey("pkcs8", …)`. Shared by
// every hand-rolled ES256 JWT signer (`apple-oauth.ts`'s SIWA client secret,
// `apns.ts`'s APNs provider token) — both sign with a `.p8` private key from
// the Apple Developer portal, same PEM shape.

export function pemToDer(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}
