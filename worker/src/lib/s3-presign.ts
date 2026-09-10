// AWS Signature V4 — query-string ("presigned URL") auth only.
//
// Cloudflare R2 speaks the S3 API but its Workers binding has no native
// presign, so we sign the request ourselves with Web Crypto (`crypto.subtle`),
// same hand-rolled-crypto posture as `session.ts` / `apple-auth.ts` — zero
// runtime dependencies. Only the pieces R2 needs: `UNSIGNED-PAYLOAD`, region
// `auto`, service `s3`, no session token.
//
// Reference: "Signature Version 4 — Query String Request Authentication"
// (AWS General Reference). The `test/media.test.ts` vector is AWS's own
// documented GET example, so this file is checked against the spec, not just
// against R2.

const ALGORITHM = "AWS4-HMAC-SHA256";

export interface PresignInput {
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  /** Host only, e.g. `<accountid>.r2.cloudflarestorage.com`. */
  host: string;
  method: "GET" | "PUT";
  /** Path from the host root, each segment already how it should appear on the
   * wire (we percent-encode it here). Leading slash required. */
  path: string;
  /** Extra headers the caller commits to sending on the actual request. `host`
   * is always signed and must not be passed here. Lower-case keys. */
  signedHeaders?: Record<string, string>;
  expiresSeconds: number;
  /** Injectable for tests. */
  now?: number;
}

/** Build a presigned URL. The returned URL carries the signature in its query
 * string; the caller issues `method` against it, sending exactly the headers in
 * `signedHeaders` (plus `Host`, which fetch sets itself). */
export async function presignS3Url(input: PresignInput): Promise<string> {
  const now = input.now ?? Date.now();
  const amzDate = toAmzDate(now); // 20130524T000000Z
  const dateStamp = amzDate.slice(0, 8); // 20130524
  const service = "s3";
  const scope = `${dateStamp}/${input.region}/${service}/aws4_request`;

  const headers: Record<string, string> = { host: input.host, ...(input.signedHeaders ?? {}) };
  const signedHeaderNames = Object.keys(headers)
    .map((h) => h.toLowerCase())
    .sort();
  const canonicalHeaders = signedHeaderNames.map((h) => `${h}:${headers[h]!.trim()}\n`).join("");
  const signedHeaders = signedHeaderNames.join(";");

  const query: Record<string, string> = {
    "X-Amz-Algorithm": ALGORITHM,
    "X-Amz-Credential": `${input.accessKeyId}/${scope}`,
    "X-Amz-Date": amzDate,
    "X-Amz-Expires": String(input.expiresSeconds),
    "X-Amz-SignedHeaders": signedHeaders,
  };
  const canonicalQuery = Object.keys(query)
    .sort()
    .map((k) => `${rfc3986(k)}=${rfc3986(query[k]!)}`)
    .join("&");

  const canonicalUri = encodePath(input.path);
  const canonicalRequest = [
    input.method,
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    "UNSIGNED-PAYLOAD",
  ].join("\n");

  const stringToSign = [ALGORITHM, amzDate, scope, await sha256Hex(canonicalRequest)].join("\n");
  const signingKey = await deriveSigningKey(input.secretAccessKey, dateStamp, input.region, service);
  const signature = hex(await hmac(signingKey, stringToSign));

  return `https://${input.host}${canonicalUri}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}

/** `20130524T000000Z` from an epoch-ms instant. */
function toAmzDate(now: number): string {
  return new Date(now).toISOString().replace(/[:-]/g, "").replace(/\.\d{3}/, "");
}

/** Percent-encode each path segment, keeping `/` as the separator. S3 signs the
 * URI encoded exactly once (unlike other AWS services). */
function encodePath(path: string): string {
  return path
    .split("/")
    .map((seg) => rfc3986(seg))
    .join("/");
}

/** RFC 3986 unreserved set is `A-Za-z0-9-_.~`; everything else is percent-
 * encoded. `encodeURIComponent` leaves `!'()*` alone, so fix those up. */
function rfc3986(str: string): string {
  return encodeURIComponent(str).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}

async function deriveSigningKey(
  secret: string,
  dateStamp: string,
  region: string,
  service: string,
): Promise<ArrayBuffer> {
  const kDate = await hmac(new TextEncoder().encode(`AWS4${secret}`), dateStamp);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, service);
  return hmac(kService, "aws4_request");
}

async function hmac(key: ArrayBuffer | Uint8Array, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message));
}

async function sha256Hex(message: string): Promise<string> {
  return hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(message)));
}

function hex(buf: ArrayBuffer): string {
  let out = "";
  for (const b of new Uint8Array(buf)) out += b.toString(16).padStart(2, "0");
  return out;
}
