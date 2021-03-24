import { TonClient } from "@tonclient/core";
import TonContract from "./ton-contract";
import deployMultisig from "./parts/deploy-multisig";
import { createClient } from "./utils/client";
import pkgNSEGiver from "../ton-packages/nse-giver.package";
import pkgJuryGroup from "../ton-packages/JuryGroup.package";
import pkgTagsResolve from "../ton-packages/TagsResolve.package";
import { utf8ToHex, utf8ToBase64, base64ToUtf8 } from "./utils/convert";
import { trimlog } from "./utils/common";
import { waitForTransaction } from "./utils/net";
import { genRandonHex } from "./utils/convert";

describe("Tags Resolve unit test", () => {
  let client: TonClient;
  let smcNSEGiver: TonContract;
  let smcJuryGroup: TonContract;
  let smcSafeMultisigWallet: TonContract;
  let smcTagsResolve: TonContract;

  before(async () => {
    trimlog(`It tests only small positive scenario.
        To test correcntly you will need to comment all JuryGruop smc's requires
        which check deployer and inbound messages.
        If you will not do that, the test will failed (and this is okay)\n`);

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

  it("deploys TagsResolve", async () => {
    smcTagsResolve = new TonContract({
      client,
      name: "TagsResolve",
      tonPackage: pkgTagsResolve,
      keys: await client.crypto.generate_random_sign_keys(),
    });

    await smcTagsResolve.calcAddress();

    await smcNSEGiver.call({
      functionName: "sendGrams",
      input: {
        dest: smcTagsResolve.address,
        amount: 100_000_000_000,
      },
    });

    trimlog(`TagsResolve address: ${smcTagsResolve.address}
            TagsResolve public: ${smcTagsResolve.keys.public}
            TagsResolve secret: ${smcTagsResolve.keys.secret}
            TagsResolve balance: ${await smcTagsResolve.getBalance()}`);

    await smcTagsResolve.deploy({
      input: {
        setup: {
          tags: [utf8ToHex("test-tag"), utf8ToHex("test-tag2")],
        },
        imageJuryGroup: pkgJuryGroup.image,
      },
    });
  });

  it("deploys JuryGroup", async () => {
    const { addrJuryGroup } = (
      await smcTagsResolve.call({ functionName: "deployJuryGroup" })
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

  it("checks addresses calculation", async () => {
    await smcTagsResolve.call({ functionName: "resolveJuryGroups" });
    console.log(
      (await smcTagsResolve.run({ functionName: "_tagsPendings" })).value
    );
    await new Promise((resolve) => setTimeout(resolve, 3000));
    console.log(
      (await smcTagsResolve.run({ functionName: "_tagsPendings" })).value
    );
    console.log((await smcTagsResolve.run({ functionName: "_members" })).value);
  });
});
