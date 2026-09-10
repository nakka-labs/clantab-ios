// Image storage (`CHECKLIST.md` "Image storage backend (R2)").
//
// One R2 bucket (`MEDIA` binding), objects namespaced by purpose. The Worker
// never proxies image bytes — it hands the client a short-lived presigned S3
// URL (`s3-presign.ts`) and R2 does the transfer. Compute/duration cost stays
// flat regardless of image volume.
//
// Keys:
//   avatars/<sha256(sub) truncated>     — one per signed-in identity
//   groups/<groupId>/cover              — one per group
//   expenses/<groupId>/<expenseId>/<id> — many per expense (receipts)

import { BadRequestError, HttpError } from "./errors.ts";
import { presignS3Url } from "./s3-presign.ts";

/** Reject anything bigger than this *before* it's uploaded — the client also
 * compresses, but per `CHECKLIST.md` we don't trust that alone. */
export const MEDIA_MAX_BYTES = 5 * 1024 * 1024;

export const MEDIA_CONTENT_TYPES = ["image/jpeg", "image/png", "image/webp"] as const;

/** Presigned URLs live 5 minutes — long enough for one upload/view on a slow
 * connection, short enough that a leaked URL is near-useless. */
const URL_TTL_SECONDS = 300;

export interface R2Credentials {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
}

/** Pull the R2 S3-API credentials from the environment, or `null` if media
 * uploads aren't configured yet (same "safe until configured" posture as
 * `APNS_*` / `ADMIN_TOKEN`). `bucket` is the binding's `bucket_name` — we read
 * it off the binding so dev/preview and prod stay in sync automatically. */
export function r2CredentialsFromEnv(env: {
  R2_ACCOUNT_ID?: string;
  R2_ACCESS_KEY_ID?: string;
  R2_SECRET_ACCESS_KEY?: string;
  R2_BUCKET?: string;
}): R2Credentials | null {
  if (!env.R2_ACCOUNT_ID || !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY || !env.R2_BUCKET) {
    return null;
  }
  return {
    accountId: env.R2_ACCOUNT_ID,
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    bucket: env.R2_BUCKET,
  };
}

/** Validate an upload's declared type and size. The presigned PUT pins both as
 * signed headers, so the client can't deviate from what we checked here. */
export function assertUploadAllowed(contentType: string, contentLength: number): void {
  if (!(MEDIA_CONTENT_TYPES as readonly string[]).includes(contentType)) {
    throw new BadRequestError(
      `Field "contentType" must be one of: ${MEDIA_CONTENT_TYPES.join(", ")}.`,
    );
  }
  if (!Number.isInteger(contentLength) || contentLength <= 0) {
    throw new BadRequestError('Field "contentLength" must be a positive integer.');
  }
  if (contentLength > MEDIA_MAX_BYTES) {
    throw new HttpError(
      413,
      "PAYLOAD_TOO_LARGE",
      `Image is ${(contentLength / (1024 * 1024)).toFixed(1)}MB; the limit is ${MEDIA_MAX_BYTES / (1024 * 1024)}MB.`,
    );
  }
}

// --- key derivation ----------------------------------------------------------

export async function avatarKey(sub: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`clantab-avatar:${sub}`));
  return `avatars/${hex(digest).slice(0, 32)}`;
}

export function groupCoverKey(groupId: string): string {
  return `groups/${groupId}/cover`;
}

export function receiptKey(groupId: string, expenseId: string, recordId: string): string {
  return `expenses/${groupId}/${expenseId}/${recordId}`;
}

/** The group a stored key belongs to, for view-time authorization — `null` for
 * keys with no group scope (avatars, which any signed-in user may view). */
export function groupIdForKey(key: string): string | null {
  const cover = /^groups\/([^/]+)\/cover$/.exec(key);
  if (cover) return cover[1]!;
  const receipt = /^expenses\/([^/]+)\/[^/]+\/[^/]+$/.exec(key);
  if (receipt) return receipt[1]!;
  if (/^avatars\/[0-9a-f]{32}$/.exec(key)) return null;
  throw new BadRequestError(`Unrecognized media key "${key}".`);
}

// --- presigning ------------------------------------------------------------

export function presignUpload(
  creds: R2Credentials,
  key: string,
  contentType: string,
  contentLength: number,
  now?: number,
): Promise<string> {
  return presignS3Url({
    accessKeyId: creds.accessKeyId,
    secretAccessKey: creds.secretAccessKey,
    region: "auto",
    host: `${creds.accountId}.r2.cloudflarestorage.com`,
    method: "PUT",
    path: `/${creds.bucket}/${key}`,
    signedHeaders: { "content-type": contentType, "content-length": String(contentLength) },
    expiresSeconds: URL_TTL_SECONDS,
    now,
  });
}

export function presignDownload(creds: R2Credentials, key: string, now?: number): Promise<string> {
  return presignS3Url({
    accessKeyId: creds.accessKeyId,
    secretAccessKey: creds.secretAccessKey,
    region: "auto",
    host: `${creds.accountId}.r2.cloudflarestorage.com`,
    method: "GET",
    path: `/${creds.bucket}/${key}`,
    expiresSeconds: URL_TTL_SECONDS,
    now,
  });
}

function hex(buf: ArrayBuffer): string {
  let out = "";
  for (const b of new Uint8Array(buf)) out += b.toString(16).padStart(2, "0");
  return out;
}
