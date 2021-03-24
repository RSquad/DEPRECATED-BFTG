import { TonClient } from "@tonclient/core";
import TonContract from "../ton-contract";
import pkgDemiurgeStore from "../../ton-packages/DemiurgeStore.package";
import pkgContest from "../../ton-packages/Contest.package";
import pkgJuryGroup from "../../ton-packages/JuryGroup.package";
import pkgJuror from "../../ton-packages/Juror.package";
import { trimlog } from "../utils/common";

export default async (client: TonClient, smcNSEGiver: TonContract) => {
  const smcDemiurgeStore = new TonContract({
    client,
    name: "DemiurgeStore",
    tonPackage: pkgDemiurgeStore,
    keys: await client.crypto.generate_random_sign_keys(),
  });

  await smcDemiurgeStore.calcAddress();

  await smcNSEGiver.call({
    functionName: "sendGrams",
    input: {
      dest: smcDemiurgeStore.address,
      amount: 100_000_000_000,
    },
  });

  trimlog(`DemiurgeStore address: ${smcDemiurgeStore.address}
              DemiurgeStore public: ${smcDemiurgeStore.keys.public}
              DemiurgeStore secret: ${smcDemiurgeStore.keys.secret}
              DemiurgeStore balance: ${await smcDemiurgeStore.getBalance()}`);

  await smcDemiurgeStore.deploy();

  await smcDemiurgeStore.call({
    functionName: "setContestImage",
    input: {
      image: pkgContest.image,
    },
  });
  await smcDemiurgeStore.call({
    functionName: "setJuryGroupImage",
    input: {
      image: pkgJuryGroup.image,
    },
  });
  await smcDemiurgeStore.call({
    functionName: "setJurorImage",
    input: {
      image: pkgJuror.image,
    },
  });

  return smcDemiurgeStore;
};
