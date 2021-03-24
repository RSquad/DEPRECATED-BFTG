import { TonClient } from "@tonclient/core";
import TonContract from "./ton-contract";
import deployMultisig from "./parts/deploy-multisig";
import { createClient } from "./utils/client";
import pkgNSEGiver from "../ton-packages/nse-giver.package";
import pkgJuryGroup from "../ton-packages/JuryGroup.package";
import pkgContest from "../ton-packages/Contest.package";
import { utf8ToHex } from "./utils/convert";
import { trimlog } from "./utils/common";
import { waitForTransaction } from "./utils/net";
import { sleep } from "./utils/common";
import deployDemiurgeStore from "./parts/deploy-demiurge-store";
import deployTestDeployer from "./parts/deploy-test-deployer";

describe("Contest unit test", () => {
  let client: TonClient;
  let smcNSEGiver: TonContract;
  let smcDemiurgeStore: TonContract;
  let smcTestDeployer: TonContract;
  let smcJuryGroup: TonContract;
  let smcSafeMultisigWallet: TonContract;
  let smcContest: TonContract;

  before(async () => {
    client = createClient();
    smcNSEGiver = new TonContract({
      client,
      name: "NSEGiver",
      tonPackage: pkgNSEGiver,
      address: process.env.NSE_GIVER_ADDRESS,
    });
  });

  it("deploys SafeMultisigWallet", async () => {
    smcSafeMultisigWallet = await deployMultisig(client, smcNSEGiver);
  });

  it("deploys DemiurgeStore", async () => {
    smcDemiurgeStore = await deployDemiurgeStore(client, smcNSEGiver);
  });

  it("deploys TestDeployer", async () => {
    smcTestDeployer = await deployTestDeployer(
      client,
      smcNSEGiver,
      smcDemiurgeStore
    );
  });

  it("deploys JuryGroup", async () => {
    const { addrJuryGroup } = (
      await smcTestDeployer.call({
        functionName: "deployJuryGroup",
        input: {
          tag: utf8ToHex("test-tag"),
        },
      })
    ).decoded.output;

    smcJuryGroup = new TonContract({
      client,
      name: "JuryGroup",
      tonPackage: pkgJuryGroup,
      address: addrJuryGroup,
    });

    trimlog(`JuryGroup address: ${smcJuryGroup.address}
            JuryGroup balance: ${await smcJuryGroup.getBalance()}`);
  });

  it("registers new member", async () => {
    const { body } = await client.abi.encode_message_body({
      abi: { type: "Contract", value: smcJuryGroup.tonPackage.abi },
      signer: { type: "None" },
      is_internal: true,
      call_set: {
        function_name: "registerMember",
        input: {
          addrMember: smcSafeMultisigWallet.address,
          pkMember: 0,
        },
      },
    });
    const { transaction } = await smcSafeMultisigWallet.call({
      functionName: "sendTransaction",
      input: {
        dest: smcJuryGroup.address,
        value: 5_000_000_000,
        flags: 3,
        bounce: true,
        payload: body,
      },
    });

    await waitForTransaction(
      client,
      {
        account_addr: { eq: smcJuryGroup.address },
        now: { ge: transaction.now },
        aborted: { eq: false },
      },
      "now aborted"
    );

    trimlog(
      `JuryGroup members: ${JSON.stringify(
        (
          await smcJuryGroup.run({
            functionName: "_members",
          })
        ).value
      )}`
    );
  });

  it("deploys Contest", async () => {
    const { addrContest } = (
      await smcTestDeployer.call({
        functionName: "deployContest",
        input: {
          store: smcDemiurgeStore.address,
          contestInfo: {
            gid: 1,
            title: utf8ToHex("title"),
            link: utf8ToHex("link"),
            hashCode: 0,
          },
          contestTimeline: {
            createdAt: 0,
            contestStarts: 0,
            contestEnds: 0,
            votingEnds: 0,
          },
          setup: {
            id: 1,
            proposalId: 1,
            tag: 1,
            groupId: 1,
            budget: 1,
            createdAt: 1,
            tags: [utf8ToHex("new-tag"), utf8ToHex("test-tag")],
          },
        },
      })
    ).decoded.output;

    smcContest = new TonContract({
      client,
      name: "Contest",
      tonPackage: pkgContest,
      address: addrContest,
    });

    trimlog(`Contest address: ${smcContest.address}
            Contest balance: ${await smcContest.getBalance()}`);

    await sleep(1000);
  });

  it("checks Contest info", async () => {
    console.log(
      (await smcContest.run({ functionName: "_juryAddresses" })).value
    );
    console.log(
      (await smcContest.run({ functionName: "_tagsPendings" })).value
    );
    console.log((await smcContest.run({ functionName: "_juryMembers" })).value);
  });
});
