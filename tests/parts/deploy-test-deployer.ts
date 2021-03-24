import { TonClient } from "@tonclient/core";
import TonContract from "../ton-contract";
import pkgTestDeployer from "../../ton-packages/TestDeployer.package";
import { sleep, trimlog } from "../utils/common";
const fs = require("fs");

export default async (
  client: TonClient,
  smcNSEGiver: TonContract,
  smcDemiurgeStore: TonContract
) => {
  const smcTestDeployer = new TonContract({
    client,
    name: "TestDeployer",
    tonPackage: pkgTestDeployer,
    keys: await client.crypto.generate_random_sign_keys(),
  });

  await smcTestDeployer.calcAddress();

  await smcNSEGiver.call({
    functionName: "sendGrams",
    input: {
      dest: smcTestDeployer.address,
      amount: 100_000_000_000,
    },
  });

  trimlog(`TestDeployer address: ${smcTestDeployer.address}
    TestDeployer public: ${smcTestDeployer.keys.public}
    TestDeployer secret: ${smcTestDeployer.keys.secret}
    TestDeployer balance: ${await smcTestDeployer.getBalance()}`);

  await smcTestDeployer.deploy({
    input: { addrStore: smcDemiurgeStore.address },
  });

  await sleep(3000);

  return smcTestDeployer;
};
