import { describe, expect, it } from "vitest";
import {
  ValidationFailure,
  assertMembersExist,
  assertPositiveAmount,
  assertSplitsSum,
} from "../src/lib/validation.ts";
import type { ExpenseSplit } from "../src/lib/types.ts";

const split = (memberId: string, amountMinor: number): ExpenseSplit => ({ memberId, amountMinor });

describe("assertPositiveAmount", () => {
  it("accepts positive integers", () => {
    expect(() => assertPositiveAmount(1)).not.toThrow();
    expect(() => assertPositiveAmount(120_00)).not.toThrow();
  });

  it.each([0, -1, 1.5, Number.NaN, "10" as unknown])("rejects %p", (value) => {
    expect(() => assertPositiveAmount(value)).toThrow(ValidationFailure);
    try {
      assertPositiveAmount(value);
    } catch (e) {
      expect((e as ValidationFailure).code).toBe("INVALID_AMOUNT");
    }
  });
});

describe("assertSplitsSum", () => {
  it("accepts splits that sum exactly", () => {
    expect(() => assertSplitsSum(1000, [split("a", 400), split("b", 600)])).not.toThrow();
  });

  it("accepts a zero share (1 minor unit split three ways → 1,0,0)", () => {
    expect(() =>
      assertSplitsSum(1, [split("a", 1), split("b", 0), split("c", 0)]),
    ).not.toThrow();
  });

  it("rejects an empty split list", () => {
    expect(() => assertSplitsSum(100, [])).toThrow(ValidationFailure);
  });

  it("rejects a sum that is off by one", () => {
    try {
      assertSplitsSum(1000, [split("a", 500), split("b", 499)]);
      expect.unreachable();
    } catch (e) {
      expect((e as ValidationFailure).code).toBe("SPLIT_MISMATCH");
    }
  });

  it("rejects a negative or non-integer share", () => {
    expect(() => assertSplitsSum(100, [split("a", 150), split("b", -50)])).toThrow(ValidationFailure);
    expect(() => assertSplitsSum(100, [split("a", 99.5), split("b", 0.5)])).toThrow(ValidationFailure);
  });
});

describe("assertMembersExist", () => {
  const group = new Set(["a", "b", "c"]);

  it("passes when every referenced id is in the group", () => {
    expect(() => assertMembersExist(["a", "c"], group)).not.toThrow();
  });

  it("throws UNKNOWN_MEMBER for a stranger", () => {
    try {
      assertMembersExist(["a", "z"], group);
      expect.unreachable();
    } catch (e) {
      expect((e as ValidationFailure).code).toBe("UNKNOWN_MEMBER");
    }
  });
});
