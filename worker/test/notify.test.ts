import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { newExpensePayload, notifyGroup, settlementPayload } from "../src/lib/notify.ts";
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
      { claimedIdentitiesExcluding: async () => ({ identities: ["apple:x"] }) },
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
        claimedIdentitiesExcluding: async (actingSub) => ({
          identities: ["apple:friend", "apple:actor"].filter((i) => i !== actingSub),
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
      { claimedIdentitiesExcluding: async () => ({ identities: ["apple:multi-device"] }) },
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
      { claimedIdentitiesExcluding: async () => ({ identities: ["apple:stale"] }) },
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
      { claimedIdentitiesExcluding: async () => ({ identities: ["apple:flaky"] }) },
      "apple:actor",
      { title: "g", body: "hi" },
      { sendPushImpl },
    );

    const tokens = await env.USER_DO.get(env.USER_DO.idFromName("apple:flaky")).deviceTokens();
    expect(tokens).toEqual(["flaky-tok"]);
  });

  it("never throws, even if claimedIdentitiesExcluding rejects", async () => {
    await expect(
      notifyGroup(
        { USER_DO: env.USER_DO, ...apnsEnv },
        {
          claimedIdentitiesExcluding: async () => {
            throw new Error("boom");
          },
        },
        "apple:actor",
        { title: "g", body: "hi" },
      ),
    ).resolves.toBeUndefined();
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
