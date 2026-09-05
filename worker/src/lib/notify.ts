// Push-notification fan-out and copy (`FEATURE_BACKLOG.md` "Push
// notifications"): after a mutation, tell every other claimed member's
// devices about it, never the actor's own. Fire-and-forget (called via
// `ctx.waitUntil` from the route handler) and best-effort throughout — a
// push failure must never affect the mutation's own response, so this never
// throws.

import { apnsConfigFromEnv, sendPush, type PushPayload } from "./apns.ts";
import type { UserDO } from "../user-do.ts";

type SendPushFn = typeof sendPush;

interface NotifyEnv {
  USER_DO: DurableObjectNamespace<UserDO>;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_TOPIC?: string;
  APNS_ENVIRONMENT?: string;
}

interface NotifiableGroup {
  claimedIdentitiesExcluding(actingSub: string): Promise<{ identities: string[] }>;
}

/** Fan a push out to every other claimed member of a group, forgetting any
 * device token APNs reports dead along the way. A no-op — not an error — if
 * APNs isn't configured yet (`NEXT_STEPS.md` Phase 6's owner action: the
 * Push Notifications capability + an APNs Auth Key from the Apple Developer
 * portal, set as the `APNS_*` Worker secrets). */
export async function notifyGroup(
  env: NotifyEnv,
  group: NotifiableGroup,
  actingSub: string,
  payload: PushPayload,
  opts: { sendPushImpl?: SendPushFn } = {},
): Promise<void> {
  const config = apnsConfigFromEnv(env);
  if (config === null) return;
  const send = opts.sendPushImpl ?? sendPush;

  try {
    const { identities } = await group.claimedIdentitiesExcluding(actingSub);
    await Promise.all(
      identities.map(async (identity) => {
        const user = env.USER_DO.get(env.USER_DO.idFromName(identity));
        const tokens = await user.deviceTokens();
        await Promise.all(
          tokens.map(async (token) => {
            const outcome = await send(config, token, payload);
            if (outcome === "unregistered") await user.unregisterDevice(token);
          }),
        );
      }),
    );
  } catch (err) {
    console.error("notifyGroup failed:", err);
  }
}

/** A locale-aware amount string ("₹500.00", "$12.34") for push bodies —
 * `Intl.NumberFormat` (native to the Workers runtime, no library). `en-IN`
 * regardless of the expense's own currency: the app's primary audience is
 * India-based (`FEATURE_BACKLOG.md`'s UPI deep link is the same call), and
 * `Intl` still resolves the right symbol/decimals for any supported ISO
 * currency from that locale. */
function formatMoney(amountMinor: number, currency: string): string {
  try {
    return new Intl.NumberFormat("en-IN", { style: "currency", currency }).format(amountMinor / 100);
  } catch {
    return `${(amountMinor / 100).toFixed(2)} ${currency}`;
  }
}

/** "Priya added ₹500 for Dinner at Toit" — `FEATURE_BACKLOG.md`'s own
 * example, and the higher-value of the two v1 notification types. */
export function newExpensePayload(opts: {
  groupId: string;
  groupName: string;
  payerName: string;
  amountMinor: number;
  currency: string;
  description: string;
}): PushPayload {
  const amount = formatMoney(opts.amountMinor, opts.currency);
  const body =
    opts.description.length > 0 ? `${opts.payerName} added ${amount} for ${opts.description}` : `${opts.payerName} added ${amount}`;
  return { title: opts.groupName, body, data: { groupId: opts.groupId, kind: "expense" } };
}

/** "Priya paid Ben ₹500" for a settlement marked paid. */
export function settlementPayload(opts: {
  groupId: string;
  groupName: string;
  fromName: string;
  toName: string;
  amountMinor: number;
  currency: string;
}): PushPayload {
  const amount = formatMoney(opts.amountMinor, opts.currency);
  return {
    title: opts.groupName,
    body: `${opts.fromName} paid ${opts.toName} ${amount}`,
    data: { groupId: opts.groupId, kind: "settlement" },
  };
}
