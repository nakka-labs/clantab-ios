import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { newExpensePayload, notifyGroup, notifyMember, reminderPayload, settlementPayload } from "../src/lib/notify.ts";
import type { ApnsConfig, ApnsOutcome } from "../src/lib/apns.ts";

const apnsEnv = { APNS_KEY_ID: "k", APNS_TEAM_ID: "t", APNS_PRIVATE_KEY: "p", APNS_TOPIC: "com.clantab.app" };

describe("notifyGroup", () => {
  it("is a no-op when APNs isn't configured", async () => {
    let called = false;
    const sendPushImpl = async (): Promise<ApnsOutcome> => {
      called = true;
      return "sent";
    };

    await notifyGroup(
      { USER_DO: env.USER_DO }, // no APNS_* — unconfigured
      { claimedRecipientsExcluding: async () => ({ recipients: [{ sub: "apple:x", memberId: "m-x" }] }) },
      "apple:actor",
      { title: "t", body: "b" },
      { sendPushImpl },
    );

    expect(called).toBe(false);
  });

  it("sends to every other claimed identity's registered devices, excluding the actor", async () => {
    await env.USER_DO.get(env.USER_DO.idFromName("apple:friend")).registerDevice("tok-friend", "ios");
    await env.USER_DO.get(env.USER_DO.idFromName("apple:actor")).registerDevice("tok-actor", "ios");

    const sent: string[] = [];
    const sendPushImpl = async (_config: ApnsConfig, token: string): Promise<ApnsOutcome> => {
      sent.push(token);
      return "sent";
    };

    await notifyGroup(
      { USER_DO: env.USER_DO, ...apnsEnv },
      {
        claimedRecipientsExcluding: async (actingSub) => ({
          recipients: [
            { sub: "apple:friend", memberId: "m-friend" },
            { sub: "apple:actor", memberId: "m-actor" },
          ].filter((r) => r.sub !== actingSub),
        }),
      },
      "apple:actor",
      { title: "g", body: "hi" },
      { sendPushImpl },
    );

    expect(sent).toEqual(["tok-friend"]);
  });

  it("sends to every device a single identity has registered", async () => {
    const user = env.USER_DO.get(env.USER_DO.idFromName("apple:multi-device"));
    await user.registerDevice("tok-phone", "ios");
    await user.registerDevice("tok-ipad", "ios");

    const sent: string[] = [];
    const sendPushImpl = async (_config: ApnsConfig, token: string): Promise<ApnsOutcome> => {
      sent.push(token);
      return "sent";
    };

    await notifyGroup(
      { USER_DO: env.USER_DO, ...apnsEnv },
      { claimedRecipientsExcluding: async () => ({ recipients: [{ sub: "apple:multi-device", memberId: "m1" }] }) },
      "apple:actor",
      { title: "g", body: "hi" },
      { sendPushImpl },
    );

    expect(sent.sort()).toEqual(["tok-ipad", "tok-phone"]);
  });

  it("forgets a device token APNs reports unregistered", async () => {
    await env.USER_DO.get(env.USER_DO.idFromName("apple:stale")).registerDevice("stale-tok", "ios");
    const sendPushImpl = async (): Promise<ApnsOutcome> => "unregistered";

    await notifyGroup(
      { USER_DO: env.USER_DO, ...apnsEnv },
      { claimedRecipientsExcluding: async () => ({ recipients: [{ sub: "apple:stale", memberId: "m1" }] }) },
      "apple:actor",
      { title: "g", body: "hi" },
      { sendPushImpl },
    );

    const tokens = await env.USER_DO.get(env.USER_DO.idFromName("apple:stale")).deviceTokens();
    expect(tokens).toEqual([]);
  });

  it("keeps a device token on a merely 'failed' outcome", async () => {
    await env.USER_DO.get(env.USER_DO.idFromName("apple:flaky")).registerDevice("flaky-tok", "ios");
    const sendPushImpl = async (): Promise<ApnsOutcome> => "failed";

    await notifyGroup(
      { USER_DO: env.USER_DO, ...apnsEnv },
      { claimedRecipientsExcluding: async () => ({ recipients: [{ sub: "apple:flaky", memberId: "m1" }] }) },
      "apple:actor",
      { title: "g", body: "hi" },
      { sendPushImpl },
    );

    const tokens = await env.USER_DO.get(env.USER_DO.idFromName("apple:flaky")).deviceTokens();
    expect(tokens).toEqual(["flaky-tok"]);
  });

  it("never throws, even if claimedRecipientsExcluding rejects", async () => {
    await expect(
      notifyGroup(
        { USER_DO: env.USER_DO, ...apnsEnv },
        {
          claimedRecipientsExcluding: async () => {
            throw new Error("boom");
          },
        },
        "apple:actor",
        { title: "g", body: "hi" },
      ),
    ).resolves.toBeUndefined();
  });

  it("folds each recipient's own net in the mutation currency into the payload data", async () => {
    const user = env.USER_DO.get(env.USER_DO.idFromName("apple:owed"));
    await user.registerDevice("tok-owed", "ios");

    const seen: Array<Record<string, string> | undefined> = [];
    const sendPushImpl = async (_c: ApnsConfig, _t: string, payload: { data?: Record<string, string> }) => {
      seen.push(payload.data);
      return "sent" as ApnsOutcome;
    };

    await notifyGroup(
      { USER_DO: env.USER_DO, ...apnsEnv },
      {
        claimedRecipientsExcluding: async () => ({
          recipients: [{ sub: "apple:owed", memberId: "m-owed" }],
        }),
      },
      "apple:actor",
      { title: "g", body: "hi", data: { groupId: "g1", kind: "expense" } },
      {
        sendPushImpl,
        recipientBalance: {
          currency: "INR",
          balances: [
            { memberId: "m-owed", currency: "INR", netMinor: 25000 },
            { memberId: "m-actor", currency: "INR", netMinor: -25000 },
          ],
        },
      },
    );

    expect(seen).toEqual([{ groupId: "g1", kind: "expense", balanceCurrency: "INR", balanceNetMinor: "25000" }]);
  });

  it("carries balanceNetMinor '0' for a recipient with no nonzero balance in that currency", async () => {
    const user = env.USER_DO.get(env.USER_DO.idFromName("apple:settled"));
    await user.registerDevice("tok-settled", "ios");

    let seen: Record<string, string> | undefined;
    const sendPushImpl = async (_c: ApnsConfig, _t: string, payload: { data?: Record<string, string> }) => {
      seen = payload.data;
      return "sent" as ApnsOutcome;
    };

    await notifyGroup(
      { USER_DO: env.USER_DO, ...apnsEnv },
      {
        claimedRecipientsExcluding: async () => ({
          recipients: [{ sub: "apple:settled", memberId: "m-settled" }],
        }),
      },
      "apple:actor",
      { title: "g", body: "hi", data: { groupId: "g1", kind: "settlement" } },
      {
        sendPushImpl,
        recipientBalance: { currency: "USD", balances: [{ memberId: "m-other", currency: "USD", netMinor: 500 }] },
      },
    );

    expect(seen).toEqual({ groupId: "g1", kind: "settlement", balanceCurrency: "USD", balanceNetMinor: "0" });
  });
});

describe("newExpensePayload", () => {
  it("names the payer and formats the amount for the group's currency", () => {
    const payload = newExpensePayload({
      groupId: "g1",
      groupName: "Flatmates",
      payerName: "Priya",
      amountMinor: 50000,
      currency: "INR",
      description: "Dinner at Toit",
    });
    expect(payload.title).toBe("Flatmates");
    expect(payload.body).toBe("Priya added ₹500.00 for Dinner at Toit");
    expect(payload.data).toEqual({ groupId: "g1", kind: "expense" });
  });

  it("omits the 'for …' clause when there's no description", () => {
    const payload = newExpensePayload({
      groupId: "g1",
      groupName: "Flatmates",
      payerName: "Priya",
      amountMinor: 50000,
      currency: "INR",
      description: "",
    });
    expect(payload.body).toBe("Priya added ₹500.00");
  });
});

describe("settlementPayload", () => {
  it("names both sides of the settlement", () => {
    const payload = settlementPayload({
      groupId: "g1",
      groupName: "Flatmates",
      fromName: "Priya",
      toName: "Ben",
      amountMinor: 50000,
      currency: "INR",
    });
    expect(payload.body).toBe("Priya paid Ben ₹500.00");
    expect(payload.data).toEqual({ groupId: "g1", kind: "settlement" });
  });
});

describe("reminderPayload", () => {
  it("names the asker and formats the amount owed", () => {
    const payload = reminderPayload({
      groupId: "g1",
      groupName: "Flatmates",
      fromName: "Priya",
      amountMinor: 50000,
      currency: "INR",
    });
    expect(payload.title).toBe("Flatmates");
    expect(payload.body).toBe("Priya sent you a reminder — you owe them ₹500.00");
    expect(payload.data).toEqual({ groupId: "g1", kind: "reminder" });
  });
});

describe("notifyMember", () => {
  it("is a no-op (returns false) when APNs isn't configured", async () => {
    let called = false;
    const sendPushImpl = async (): Promise<ApnsOutcome> => {
      called = true;
      return "sent";
    };

    const sent = await notifyMember({ USER_DO: env.USER_DO }, "apple:target", { title: "t", body: "b" }, { sendPushImpl });

    expect(sent).toBe(false);
    expect(called).toBe(false);
  });

  it("sends to every device the one target identity has registered", async () => {
    const user = env.USER_DO.get(env.USER_DO.idFromName("apple:reminded"));
    await user.registerDevice("tok-phone", "ios");
    await user.registerDevice("tok-ipad", "ios");

    const sentTokens: string[] = [];
    const sendPushImpl = async (_c: ApnsConfig, token: string): Promise<ApnsOutcome> => {
      sentTokens.push(token);
      return "sent";
    };

    const sent = await notifyMember({ USER_DO: env.USER_DO, ...apnsEnv }, "apple:reminded", { title: "g", body: "hi" }, { sendPushImpl });

    expect(sent).toBe(true);
    expect(sentTokens.sort()).toEqual(["tok-ipad", "tok-phone"]);
  });

  it("returns false and forgets the token when APNs reports it unregistered", async () => {
    await env.USER_DO.get(env.USER_DO.idFromName("apple:stale-remind")).registerDevice("stale-tok", "ios");
    const sendPushImpl = async (): Promise<ApnsOutcome> => "unregistered";

    const sent = await notifyMember({ USER_DO: env.USER_DO, ...apnsEnv }, "apple:stale-remind", { title: "g", body: "hi" }, { sendPushImpl });

    expect(sent).toBe(false);
    const tokens = await env.USER_DO.get(env.USER_DO.idFromName("apple:stale-remind")).deviceTokens();
    expect(tokens).toEqual([]);
  });

  it("returns false when the target has no registered devices", async () => {
    const sent = await notifyMember({ USER_DO: env.USER_DO, ...apnsEnv }, "apple:no-devices", { title: "g", body: "hi" });
    expect(sent).toBe(false);
  });

  it("never throws", async () => {
    const sendPushImpl = async (): Promise<ApnsOutcome> => {
      throw new Error("boom");
    };
    await env.USER_DO.get(env.USER_DO.idFromName("apple:boom")).registerDevice("tok", "ios");
    await expect(
      notifyMember({ USER_DO: env.USER_DO, ...apnsEnv }, "apple:boom", { title: "g", body: "hi" }, { sendPushImpl }),
    ).resolves.toBe(false);
  });
});
