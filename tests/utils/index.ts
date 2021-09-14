import {TonContract} from '@rsquad/ton-utils';
import {sendThroughMultisig} from '@rsquad/ton-utils/dist/net';
import pkgSafeMultisigWallet from '../../ton-packages/SafeMultisigWallet.package';
import {TonClient} from '@tonclient/core';
import {TonPackage} from '@rsquad/ton-utils/dist/ton-contract';

export const createMultisig = (client: TonClient) =>
  new TonContract({
    client,
    name: 'SafeMultisigWallet',
    tonPackage: pkgSafeMultisigWallet,
    address: process.env.MULTISIG_ADDRESS,
    keys: {
      public: process.env.MULTISIG_PUBKEY,
      secret: process.env.MULTISIG_SECRET,
    },
  });

export const deployDirectly = async ({
  client,
  smcSafeMultisigWallet,
  name,
  tonPackage,
  input = {},
}: {
  client: TonClient;
  smcSafeMultisigWallet: TonContract;
  name: string;
  tonPackage: TonPackage;
  input?: any;
}) => {
  const smc = new TonContract({
    client,
    name: name,
    tonPackage: tonPackage,
    keys: await client.crypto.generate_random_sign_keys(),
  });
  await smc.calcAddress();

  await sendThroughMultisig({
    smcSafeMultisigWallet,
    dest: smc.address,
    value: 5_000_000_000,
  });

  await smc.deploy({input});
  return smc;
};
