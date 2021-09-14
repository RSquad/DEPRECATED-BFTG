import {TonClient} from '@tonclient/core';
import {createClient, TonContract} from '@rsquad/ton-utils';
import {createMultisig, deployDirectly} from '../utils';
import pkgTestDecode from '../../ton-packages/TestDecode.package';
import {utf8ToHex} from '@rsquad/ton-utils/dist/convert';
import {logPubGetter} from '../../utils/common';

describe('SmvRoot unit test', () => {
  let client: TonClient;
  let smcSafeMultisigWallet: TonContract;
  let smcTestDecode: TonContract;

  before(async () => {
    client = createClient();
    smcSafeMultisigWallet = createMultisig(client);

    smcTestDecode = await deployDirectly({
      client,
      smcSafeMultisigWallet,
      name: '',
      tonPackage: pkgTestDecode,
    });
  });

  it('encode', async () => {
    await smcTestDecode.call({
      functionName: 'encode',
      input: {
        specific: {
          tags: [utf8ToHex('hello'), utf8ToHex('world')],
          underwayDuration: 100,
          prizePool: 100,
          description: utf8ToHex('description'),
        },
      },
    });
  });

  it('decode', async () => {
    await smcTestDecode.call({
      functionName: 'decode',
    });

    await logPubGetter('decoded', smcTestDecode, '_specificDecoded');
  });
});
