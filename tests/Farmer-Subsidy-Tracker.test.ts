import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const address4 = accounts.get("wallet_4")!;
const contractOwner = accounts.get("deployer")!;

const contractName = "Farmer-Subsidy-Tracker";

describe("Farmer Subsidy Tracker - Mutual Aid Fund", () => {
  // Helper function to register a farmer
  const registerFarmer = (address: string, name: string, farmSize: number, location: string) => {
    return simnet.callPublicFn(
      contractName,
      "register-farmer",
      [`"${name}"`, farmSize.toString(), `"${location}"`],
      address
    );
  };

  // Helper function to verify a farmer
  const verifyFarmer = (farmerAddress: string) => {
    return simnet.callPublicFn(
      contractName,
      "verify-farmer",
      [farmerAddress],
      contractOwner
    );
  };

  // Helper function to contribute to mutual aid
  const contributeToMutualAid = (address: string, amount: number) => {
    return simnet.callPublicFn(
      contractName,
      "contribute-to-mutual-aid",
      [amount.toString()],
      address
    );
  };

  // Helper function to create aid request
  const createAidRequest = (address: string, amount: number, reason: string) => {
    return simnet.callPublicFn(
      contractName,
      "create-aid-request",
      [amount.toString(), `u"${reason}"`],
      address
    );
  };

  // Helper function to vote on aid request
  const voteOnAidRequest = (address: string, requestId: number, vote: boolean) => {
    return simnet.callPublicFn(
      contractName,
      "vote-on-aid-request",
      [requestId.toString(), vote.toString()],
      address
    );
  };

  describe("Mutual Aid Fund - Setup and Basic Functionality", () => {
    it("ensures simnet is well initialised", () => {
      expect(simnet.blockHeight).toBeDefined();
    });

    it("initializes mutual aid pool with zero balance", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-mutual-aid-pool-balance",
        [],
        address1
      );
      expect(result).toBeUint(0);
    });

    it("returns correct mutual aid statistics", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-mutual-aid-stats",
        [],
        address1
      );
      expect(result).toBeTuple();
      expect(result).toHaveProperty("pool-balance");
      expect(result).toHaveProperty("total-requests");
      expect(result).toHaveProperty("minimum-contribution");
      expect(result).toHaveProperty("minimum-votes-required");
    });
  });

  describe("Mutual Aid Fund - Farmer Registration and Contributions", () => {
    it("allows registered and verified farmers to contribute", () => {
      // Register farmer
      const registerResult = registerFarmer(address1, "John Doe", 100, "Farm Location 1");
      expect(registerResult.result).toBeOk(true);

      // Verify farmer
      const verifyResult = verifyFarmer(address1);
      expect(verifyResult.result).toBeOk(true);

      // Contribute to mutual aid (minimum is 1000000 STX)
      const contributeResult = contributeToMutualAid(address1, 2000000);
      expect(contributeResult.result).toBeOk(true);

      // Check pool balance
      const { result: poolBalance } = simnet.callReadOnlyFn(
        contractName,
        "get-mutual-aid-pool-balance",
        [],
        address1
      );
      expect(poolBalance).toBeUint(2000000);
    });

    it("rejects contributions below minimum amount", () => {
      // Register and verify farmer
      registerFarmer(address2, "Jane Smith", 150, "Farm Location 2");
      verifyFarmer(address2);

      // Try to contribute below minimum (999999 < 1000000)
      const contributeResult = contributeToMutualAid(address2, 999999);
      expect(contributeResult.result).toBeErr(300); // ERR_INSUFFICIENT_CONTRIBUTION
    });

    it("rejects contributions from unregistered farmers", () => {
      const contributeResult = contributeToMutualAid(address3, 2000000);
      expect(contributeResult.result).toBeErr(101); // ERR_FARMER_NOT_FOUND
    });

    it("tracks farmer contributions accurately", () => {
      // First contribution should be recorded from previous test
      const { result: contributions } = simnet.callReadOnlyFn(
        contractName,
        "get-farmer-contributions",
        [address1],
        address1
      );
      expect(contributions).toBeSome();
      if (contributions.type === "some") {
        expect(contributions.value).toHaveProperty("total-contributed");
        expect(contributions.value).toHaveProperty("contribution-count");
        expect(contributions.value).toHaveProperty("last-contribution-block");
      }
    });
  });

  describe("Mutual Aid Fund - Aid Request Creation", () => {
    it("allows verified farmers to create aid requests", () => {
      // Ensure we have contributions in the pool first
      registerFarmer(address3, "Bob Johnson", 200, "Farm Location 3");
      verifyFarmer(address3);

      const requestResult = createAidRequest(address3, 500000, "Emergency crop irrigation needed");
      expect(requestResult.result).toBeOk(0); // First request ID should be 0
    });

    it("validates request amount and reason", () => {
      // Try to create request with zero amount
      const zeroAmountResult = createAidRequest(address3, 0, "Valid reason");
      expect(zeroAmountResult.result).toBeErr(102); // ERR_INVALID_AMOUNT

      // Try to create request with empty reason
      const emptyReasonResult = createAidRequest(address3, 100000, "");
      expect(emptyReasonResult.result).toBeErr(102); // ERR_INVALID_AMOUNT
    });

    it("rejects requests exceeding pool balance", () => {
      const excessiveAmountResult = createAidRequest(address3, 10000000, "Too much money");
      expect(excessiveAmountResult.result).toBeErr(304); // ERR_INSUFFICIENT_POOL_FUNDS
    });

    it("assigns unique request IDs sequentially", () => {
      const request1 = createAidRequest(address3, 100000, "First request");
      expect(request1.result).toBeOk(1);

      const request2 = createAidRequest(address3, 150000, "Second request");
      expect(request2.result).toBeOk(2);
    });

    it("stores request details correctly", () => {
      const { result: requestDetails } = simnet.callReadOnlyFn(
        contractName,
        "get-aid-request",
        ["0"],
        address1
      );
      expect(requestDetails).toBeSome();
      if (requestDetails.type === "some") {
        expect(requestDetails.value).toHaveProperty("farmer");
        expect(requestDetails.value).toHaveProperty("amount-requested");
        expect(requestDetails.value).toHaveProperty("reason");
        expect(requestDetails.value).toHaveProperty("status");
      }
    });
  });

  describe("Mutual Aid Fund - Voting Mechanism", () => {
    it("allows contributing farmers to vote on requests", () => {
      // address1 already contributed, so they can vote
      const voteResult = voteOnAidRequest(address1, 0, true);
      expect(voteResult.result).toBeOk(true);
    });

    it("prevents double voting", () => {
      // address1 already voted on request 0
      const doubleVoteResult = voteOnAidRequest(address1, 0, false);
      expect(doubleVoteResult.result).toBeErr(302); // ERR_ALREADY_VOTED
    });

    it("prevents non-contributors from voting", () => {
      // address4 hasn't contributed
      registerFarmer(address4, "Alice Brown", 80, "Farm Location 4");
      verifyFarmer(address4);

      const voteResult = voteOnAidRequest(address4, 0, true);
      expect(voteResult.result).toBeErr(305); // ERR_NOT_ELIGIBLE_VOTER
    });

    it("updates vote counts correctly", () => {
      // Make address2 contribute so they can vote
      contributeToMutualAid(address2, 1500000);
      
      // Vote for the request
      voteOnAidRequest(address2, 0, true);
      
      const { result: voteStats } = simnet.callReadOnlyFn(
        contractName,
        "get-aid-request-votes",
        ["0"],
        address1
      );
      expect(voteStats).toBeSome();
      if (voteStats.type === "some") {
        expect(voteStats.value).toHaveProperty("votes-for");
        expect(voteStats.value).toHaveProperty("votes-against");
        expect(voteStats.value).toHaveProperty("total-votes");
      }
    });

    it("tracks individual voting status", () => {
      const hasVoted = simnet.callReadOnlyFn(
        contractName,
        "has-voted-on-request",
        ["0", address1],
        address1
      );
      expect(hasVoted.result).toBeTrue();

      const hasNotVoted = simnet.callReadOnlyFn(
        contractName,
        "has-voted-on-request",
        ["0", address4],
        address1
      );
      expect(hasNotVoted.result).toBeFalse();
    });
  });

  describe("Mutual Aid Fund - Request Finalization", () => {
    it("approves requests with sufficient positive votes", () => {
      // Get another contributor to vote
      contributeToMutualAid(address3, 1000000);
      voteOnAidRequest(address3, 0, true);

      // Now finalize the request (should have 3 votes for, 0 against)
      const finalizeResult = simnet.callPublicFn(
        contractName,
        "finalize-aid-request",
        ["0"],
        address1
      );
      expect(finalizeResult.result).toBeOk("approved");
    });

    it("rejects requests with insufficient votes", () => {
      // Create a new request
      const newRequestResult = createAidRequest(address3, 200000, "Need help with seeds");
      const requestId = newRequestResult.result;
      
      // Try to finalize without enough votes (minimum is 3)
      const finalizeResult = simnet.callPublicFn(
        contractName,
        "finalize-aid-request",
        [requestId.toString()],
        address1
      );
      expect(finalizeResult.result).toBeErr(306); // ERR_INVALID_REQUEST_STATUS
    });

    it("prevents finalization of already resolved requests", () => {
      // Try to finalize the already approved request (ID 0)
      const finalizeResult = simnet.callPublicFn(
        contractName,
        "finalize-aid-request",
        ["0"],
        address1
      );
      expect(finalizeResult.result).toBeErr(303); // ERR_REQUEST_ALREADY_RESOLVED
    });

    it("updates pool balance after successful disbursement", () => {
      // Check that pool balance decreased after the approved request
      const { result: poolBalance } = simnet.callReadOnlyFn(
        contractName,
        "get-mutual-aid-pool-balance",
        [],
        address1
      );
      // Should be less than the sum of all contributions (4500000) minus disbursed amount (500000)
      expect(poolBalance).toBeUint(4000000);
    });
  });

  describe("Mutual Aid Fund - Emergency Withdrawal", () => {
    it("allows contributors to withdraw with penalty", () => {
      // address1 contributed 2000000, let them withdraw 1000000
      const withdrawResult = simnet.callPublicFn(
        contractName,
        "withdraw-contribution",
        ["1000000"],
        address1
      );
      // Should receive 900000 after 10% penalty
      expect(withdrawResult.result).toBeOk(900000);
    });

    it("prevents withdrawal of more than contributed", () => {
      // address1 now has contributed 1000000 remaining after withdrawal
      const excessiveWithdrawal = simnet.callPublicFn(
        contractName,
        "withdraw-contribution",
        ["2000000"],
        address1
      );
      expect(excessiveWithdrawal.result).toBeErr(300); // ERR_INSUFFICIENT_CONTRIBUTION
    });

    it("prevents withdrawal by non-contributors", () => {
      const withdrawResult = simnet.callPublicFn(
        contractName,
        "withdraw-contribution",
        ["100000"],
        address4
      );
      expect(withdrawResult.result).toBeErr(101); // ERR_FARMER_NOT_FOUND (no contributions)
    });
  });

  describe("Mutual Aid Fund - Edge Cases and Error Handling", () => {
    it("handles requests for non-existent IDs", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-aid-request",
        ["999"],
        address1
      );
      expect(result).toBeNone();
    });

    it("handles voting on non-existent requests", () => {
      const voteResult = voteOnAidRequest(address1, 999, true);
      expect(voteResult.result).toBeErr(301); // ERR_REQUEST_NOT_FOUND
    });

    it("handles contributions query for non-contributors", () => {
      const { result } = simnet.callReadOnlyFn(
        contractName,
        "get-farmer-contributions",
        [address4],
        address1
      );
      expect(result).toBeNone();
    });

    it("maintains data consistency across multiple operations", () => {
      // Verify the mutual aid stats are consistent
      const { result: stats } = simnet.callReadOnlyFn(
        contractName,
        "get-mutual-aid-stats",
        [],
        address1
      );
      expect(stats).toHaveProperty("pool-balance");
      expect(stats).toHaveProperty("total-requests");
      
      // Verify pool balance matches expected value after all operations
      const { result: poolBalance } = simnet.callReadOnlyFn(
        contractName,
        "get-mutual-aid-pool-balance",
        [],
        address1
      );
      // Original: 4500000, minus 500000 disbursed, minus 900000 withdrawn (1000000 - 100000 penalty) = 3100000
      expect(poolBalance).toBeUint(3100000);
    });
  });
});
