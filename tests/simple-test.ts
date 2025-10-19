import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const contractOwner = accounts.get("deployer")!;
const contractName = "Farmer-Subsidy-Tracker";

describe("Simple Mutual Aid Fund Tests", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("checks initial pool balance is zero", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-mutual-aid-pool-balance",
      [],
      address1
    );
    expect(result).toBeUint(0);
  });

  it("registers a farmer successfully", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "register-farmer",
      ["\"John Doe\"", "100", "\"Farm Location 1\""],
      address1
    );
    expect(result).toBeOk(true);
  });

  it("verifies a farmer", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "verify-farmer",
      [address1],
      contractOwner
    );
    expect(result).toBeOk(true);
  });

  it("allows farmer to contribute to mutual aid pool", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "contribute-to-mutual-aid",
      ["2000000"],
      address1
    );
    expect(result).toBeOk(true);
  });

  it("checks pool balance after contribution", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-mutual-aid-pool-balance",
      [],
      address1
    );
    expect(result).toBeUint(2000000);
  });
});
