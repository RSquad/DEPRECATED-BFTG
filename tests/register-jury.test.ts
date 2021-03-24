import { TonClient } from "@tonclient/core";
import TonContract from "./ton-contract";
import deployMultisig from "./parts/deploy-multisig";
import deployDemiurgeStore from "./parts/deploy-demiurge-store";
import { createClient } from "./utils/client";
import pkgNSEGiver from "../ton-packages/nse-giver.package";
import pkgJuryGroup from "../ton-packages/JuryGroup.package";
import pkgJurorContract from "../ton-packages/JurorContract.package";
import pkgDemiurge from "../ton-packages/Demiurge.package";
import { utf8ToHex } from "./utils/convert";
import { trimlog } from "./utils/common";
import { sleep } from "./utils/common";
import { callThroughMultisig } from "./utils/net";

describe("Register jury test", () => {
  let client: TonClient;
  let smcNSEGiver: TonContract;
  let smcDemiurgeStore: TonContract;
  let smcDemiurge: TonContract;
  let smcSafeMultisigWallet: TonContract;
  let smcJuryGroup: TonContract;
  let smcJurorContract: TonContract;

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

  it("deploys Demiurge", async () => {
    smcDemiurge = new TonContract({
      client,
      name: "Demiurge",
      tonPackage: pkgDemiurge,
      keys: await client.crypto.generate_random_sign_keys(),
    });

    await smcDemiurge.calcAddress();

    await smcNSEGiver.call({
      functionName: "sendGrams",
      input: {
        dest: smcDemiurge.address,
        amount: 100_000_000_000,
      },
    });

    trimlog(`Demiurge address: ${smcDemiurge.address}
            Demiurge public: ${smcDemiurge.keys.public}
            Demiurge secret: ${smcDemiurge.keys.secret}
            Demiurge balance: ${await smcDemiurge.getBalance()}`);

    await smcDemiurge.deploy({
      input: {
        store: smcDemiurgeStore.address,
        initJuryKeys: [
          `0x${(await client.crypto.generate_random_sign_keys()).public}`,
        ],
      },
    });

    await sleep(1000);
  });

  it("registers new jury member with new group", async () => {
    const memberKey = `0x${
      (await client.crypto.generate_random_sign_keys()).public
    }`;
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcDemiurge.tonPackage.abi,
      functionName: "registerJuryMember",
      input: {
        tag: utf8ToHex("new-tag"),
        pk: memberKey,
      },
      dest: smcDemiurge.address,
      value: 10_000_000_000,
    });

    await sleep(1000);

    const addrJuryGroup = (
      await smcDemiurge.run({
        functionName: "resolveJuryGroup",
        input: { tag: utf8ToHex("new-tag") },
      })
    ).value.addr;

    smcJuryGroup = new TonContract({
      client,
      name: "JuryGroup",
      tonPackage: pkgJuryGroup,
      address: addrJuryGroup,
    });

    trimlog(`JuryGroup address: ${smcJuryGroup.address}
        JuryGroup balance: ${await smcJuryGroup.getBalance()}
        JuryGroup members: ${JSON.stringify(
          (
            await smcJuryGroup.run({
              functionName: "_members",
            })
          ).value
        )}`);

    const addrJurorContract = (
      await smcDemiurge.run({
        functionName: "resolveJuror",
        input: { pk: memberKey },
      })
    ).value.addr;

    smcJurorContract = new TonContract({
      client,
      name: "JurorContract",
      tonPackage: pkgJurorContract,
      address: addrJurorContract,
    });

    trimlog(`JurorContract address: ${smcJurorContract.address}
        JurorContract balance: ${await smcJurorContract.getBalance()}`);
  });

  it("registers new jury member to existed group", async () => {
    const memberKey = `0x${
      (await client.crypto.generate_random_sign_keys()).public
    }`;
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcDemiurge.tonPackage.abi,
      functionName: "registerJuryMember",
      input: {
        tag: utf8ToHex("new-tag"),
        pk: memberKey,
      },
      dest: smcDemiurge.address,
      value: 10_000_000_000,
    });

    await sleep(1000);

    const addrJuryGroup = (
      await smcDemiurge.run({
        functionName: "resolveJuryGroup",
        input: { tag: utf8ToHex("new-tag") },
      })
    ).value.addr;

    smcJuryGroup = new TonContract({
      client,
      name: "JuryGroup",
      tonPackage: pkgJuryGroup,
      address: addrJuryGroup,
    });

    trimlog(`JuryGroup address: ${smcJuryGroup.address}
        JuryGroup balance: ${await smcJuryGroup.getBalance()}
        JuryGroup members: ${JSON.stringify(
          (
            await smcJuryGroup.run({
              functionName: "_members",
            })
          ).value
        )}`);

    const addrJurorContract = (
      await smcDemiurge.run({
        functionName: "resolveJuror",
        input: { pk: memberKey },
      })
    ).value.addr;

    smcJurorContract = new TonContract({
      client,
      name: "JurorContract",
      tonPackage: pkgJurorContract,
      address: addrJurorContract,
    });

    trimlog(`smcJurorContract address: ${smcJurorContract.address}
        smcJurorContract balance: ${await smcJurorContract.getBalance()}`);
  });

  it("registers new jury member to existed group two times", async () => {
    const memberKey = `0x${
      (await client.crypto.generate_random_sign_keys()).public
    }`;
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcDemiurge.tonPackage.abi,
      functionName: "registerJuryMember",
      input: {
        tag: utf8ToHex("new-tag"),
        pk: memberKey,
      },
      dest: smcDemiurge.address,
      value: 10_000_000_000,
    });

    await sleep(1000);

    const addrJuryGroup = (
      await smcDemiurge.run({
        functionName: "resolveJuryGroup",
        input: { tag: utf8ToHex("new-tag") },
      })
    ).value.addr;

    smcJuryGroup = new TonContract({
      client,
      name: "JuryGroup",
      tonPackage: pkgJuryGroup,
      address: addrJuryGroup,
    });

    trimlog(`JuryGroup address: ${smcJuryGroup.address}
        JuryGroup balance: ${await smcJuryGroup.getBalance()}
        JuryGroup members: ${JSON.stringify(
          (
            await smcJuryGroup.run({
              functionName: "_members",
            })
          ).value
        )}`);

    const addrJurorContract = (
      await smcDemiurge.run({
        functionName: "resolveJuror",
        input: { pk: memberKey },
      })
    ).value.addr;

    smcJurorContract = new TonContract({
      client,
      name: "JurorContract",
      tonPackage: pkgJurorContract,
      address: addrJurorContract,
    });

    trimlog(`smcJurorContract address: ${smcJurorContract.address}
        smcJurorContract balance: ${await smcJurorContract.getBalance()}`);

    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcDemiurge.tonPackage.abi,
      functionName: "registerJuryMember",
      input: {
        tag: utf8ToHex("new-tag"),
        pk: memberKey,
      },
      dest: smcDemiurge.address,
      value: 15_000_000_000,
    });

    trimlog(`JuryGroup address: ${smcJuryGroup.address}
        JuryGroup balance: ${await smcJuryGroup.getBalance()}
        JuryGroup members: ${JSON.stringify(
          (
            await smcJuryGroup.run({
              functionName: "_members",
            })
          ).value
        )}`);
  });
});
