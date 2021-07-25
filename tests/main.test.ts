import {TonClient} from '@tonclient/core';
import {createClient} from '../utils/client';
import TonContract from '../utils/ton-contract';
import pkgSafeMultisigWallet from '../ton-packages/SafeMultisigWallet.package';
import initChunk from './init.chunk';

describe('main test', () => {
  let client: TonClient;
  let smcSafeMultisigWallet: TonContract;
  let smcBftgRootStore: TonContract;
  let smcBftgRoot: TonContract;
  let smcSmvRootStore: TonContract;
  let smcSmvRoot: TonContract;

  before(async () => {
    client = createClient();
    smcSafeMultisigWallet = new TonContract({
      client,
      name: 'SafeMultisigWallet',
      tonPackage: pkgSafeMultisigWallet,
      address: process.env.MULTISIG_ADDRESS,
      keys: {
        public: process.env.MULTISIG_PUBKEY,
        secret: process.env.MULTISIG_SECRET,
      },
    });
  });

  it('run system initialization', async () => {
    const contracts = await initChunk(client, smcSafeMultisigWallet);
    smcBftgRootStore = contracts.smcBftgRootStore;
    smcBftgRoot = contracts.smcBftgRoot;
    smcSmvRootStore = contracts.smcSmvRootStore;
    smcSmvRoot = contracts.smcSmvRoot;
  });
});
