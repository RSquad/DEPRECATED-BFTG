import { TonClient } from "@tonclient/core";
import TonContract from "./ton-contract";
import deployMultisig from "./parts/deploy-multisig";
import { createClient } from "./utils/client";
import pkgNSEGiver from "../ton-packages/nse-giver.package";
import pkgVoting from "../ton-packages/Voting.package";
import { utf8ToHex, utf8ToBase64, base64ToUtf8 } from "./utils/convert";
import { trimlog } from "./utils/common";
import { genRandonHex } from "./utils/convert";

describe("Voting unit test", () => {
  let client: TonClient;
  let smcNSEGiver: TonContract;
  let smcVoting: TonContract;
  let smcSafeMultisigWallet: TonContract;

  let evaluation = {
    entryId: 1,
    voteType: 1,
    score: 8,
    comment: utf8ToHex("comment"),
  };

  let evalHash = "";
  let evalEncoded = "";
  const evalKey = `0x${genRandonHex(64)}`;

  before(async () => {
    trimlog(`It tests only small positive scenario of non-prod contract.\n`);

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

  it("deploys Voting", async () => {
    smcVoting = new TonContract({
      client,
      name: "Voting",
      tonPackage: pkgVoting,
      keys: await client.crypto.generate_random_sign_keys(),
    });

    await smcVoting.calcAddress();

    await smcNSEGiver.call({
      functionName: "sendGrams",
      input: {
        dest: smcVoting.address,
        amount: 100_000_000_000,
      },
    });

    trimlog(`Voting address: ${smcVoting.address}
        Voting public: ${smcVoting.keys.public}
        Voting secret: ${smcVoting.keys.secret}
        Voting balance: ${await smcVoting.getBalance()}`);

    await smcVoting.deploy();
  });

  it("calculates evaluation hash", async () => {
    evalHash = (
      await smcVoting.run({
        functionName: "hashEvaluation",
        input: {
          evaluation,
        },
      })
    ).value.hash;
  });

  it("calculates evaluation encoded", async () => {
    evalEncoded = (
      await client.crypto.chacha20({
        data: utf8ToBase64(JSON.stringify(evaluation)),
        key: evalKey,
        nonce: "000000000000000000000000",
      })
    ).data;
  });

  it("votes hidden", async () => {
    await smcVoting.call({
      functionName: "voteHidden",
      input: {
        hiddenVote: {
          entryId: 1,
          hash: evalHash,
          encoded: "",
        },
      },
    });
  });

  it("reveals hidden vote", async () => {
    evaluation = JSON.parse(
      base64ToUtf8(
        (
          await client.crypto.chacha20({
            data: evalEncoded,
            key: evalKey,
            nonce: "000000000000000000000000",
          })
        ).data
      )
    );
    await smcVoting.call({
      functionName: "revealHiddenVote",
      input: {
        evaluation,
      },
    });
  });

  it("checks revealed marks and comments", async () => {
    console.log(
      (
        await smcVoting.run({
          functionName: "_hiddenVotes",
        })
      ).value
    );
    console.log(
      (
        await smcVoting.run({
          functionName: "_marks",
        })
      ).value
    );
    console.log(
      (
        await smcVoting.run({
          functionName: "_comments",
        })
      ).value
    );
  });
});
