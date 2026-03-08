import { describe, expect, it } from "vitest";
import { generateOpenPayAccountNumber, isPlaceholderOpenPayAccount } from "@/lib/openpayIdentity";

describe("openpayIdentity", () => {
  it("generates deterministic account numbers", () => {
    expect(generateOpenPayAccountNumber("00000000-0000-0000-0000-000000000000")).toBe(
      "OP00000000000000000000000000000000",
    );
  });

  it("detects placeholder OpenPay account identity", () => {
    expect(isPlaceholderOpenPayAccount("OpenPay User", "openpay")).toBe(true);
    expect(isPlaceholderOpenPayAccount("OpenPay User", "OPENPAY")).toBe(true);
    expect(isPlaceholderOpenPayAccount("Jane Doe", "jane_doe")).toBe(false);
  });
});

