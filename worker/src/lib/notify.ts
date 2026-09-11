// Push-notification fan-out and copy (`FEATURE_BACKLOG.md` "Push
// notifications"): after a mutation, tell every other claimed member's
// devices about it, never the actor's own. Fire-and-forget (called via
// `ctx.waitUntil` from the route handler) and best-effort throughout — a
// push failure must never affect the mutation's own response, so this never
// throws.

import { apnsConfigFromEnv, sendPush, type PushPayload } from "./apns.ts";
import type { UserDO } from "../user-do.ts";
import type { Balance } from "./types.ts";

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
  claimedRecipientsExcluding(actingSub: string): Promise<{ recipients: { sub: string; memberId: string }[] }>;
}

/** The post-mutation balance state to fold into each recipient's payload
 * (`CHECKLIST.md` "push payload carries the recipient's own updated
 * balance"): the full `balances` array from the same `getState()` the route
 * handler already read, plus the currency of the mutation this push is
 * about. Each recipient gets *their own* net in that currency — `"0"` when
 * they have no nonzero balance in it — so the app can update its cached
 * dashboard figure without a fetch. */
interface RecipientBalanceContext {
  currency: string;
  balances: Balance[];
}

/** This member's net (minor units) in `currency`, or 0 when they have no
 * nonzero balance there — `computeBalances` omits zero buckets. */
function netMinorFor(balances: Balance[], memberId: string, currency: string): number {
  return balances.find((b) => b.memberId === memberId && b.currency === currency)?.netMinor ?? 0;
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
  opts: { sendPushImpl?: SendPushFn; recipientBalance?: RecipientBalanceContext } = {},
): Promise<void> {
  const config = apnsConfigFromEnv(env);
  if (config === null) return;
  const send = opts.sendPushImpl ?? sendPush;

  try {
    const { recipients } = await group.claimedRecipientsExcluding(actingSub);
    await Promise.all(
      recipients.map(async ({ sub, memberId }) => {
        const user = env.USER_DO.get(env.USER_DO.idFromName(sub));
        const tokens = await user.deviceTokens();
        const recipientPayload = opts.recipientBalance
          ? {
              ...payload,
              data: {
                ...payload.data,
                balanceCurrency: opts.recipientBalance.currency,
                balanceNetMinor: String(
                  netMinorFor(opts.recipientBalance.balances, memberId, opts.recipientBalance.currency),
                ),
              },
            }
          : payload;
        await Promise.all(
          tokens.map(async (token) => {
            const outcome = await send(config, token, recipientPayload);
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

/** "Priya sent you a reminder — you owe them ₹500" for the "Remind" button on
 * an outstanding balance (`CHECKLIST.md`): the opposite direction of
 * `BalanceAgingScheduler`, which only ever nudges *you* about what you owe. */
export function reminderPayload(opts: {
  groupId: string;
  groupName: string;
  fromName: string;
  amountMinor: number;
  currency: string;
}): PushPayload {
  const amount = formatMoney(opts.amountMinor, opts.currency);
  return {
    title: opts.groupName,
    body: `${opts.fromName} sent you a reminder — you owe them ${amount}`,
    data: { groupId: opts.groupId, kind: "reminder" },
  };
}

/** Push exactly one identity's devices — the narrow counterpart to
 * `notifyGroup`'s broadcast, for a "Remind" push that targets one specific
 * person rather than every other claimed member. Same best-effort contract
 * (never throws, forgets dead tokens along the way) but returns whether
 * anything was actually delivered, since the route's own response reports
 * that back to the caller (`{ sent: boolean }`) rather than firing-and-forgetting
 * via `ctx.waitUntil`. */
export async function notifyMember(
  env: NotifyEnv,
  sub: string,
  payload: PushPayload,
  opts: { sendPushImpl?: SendPushFn } = {},
): Promise<boolean> {
  const config = apnsConfigFromEnv(env);
  if (config === null) return false;
  const send = opts.sendPushImpl ?? sendPush;

  try {
    const user = env.USER_DO.get(env.USER_DO.idFromName(sub));
    const tokens = await user.deviceTokens();
    let sent = false;
    await Promise.all(
      tokens.map(async (token) => {
        const outcome = await send(config, token, payload);
        if (outcome === "unregistered") await user.unregisterDevice(token);
        else sent = true;
      }),
    );
    return sent;
  } catch (err) {
    console.error("notifyMember failed:", err);
    return false;
  }
}
