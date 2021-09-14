import {TonClient} from '@tonclient/core';
import {createClient, TonContract} from '@rsquad/ton-utils';
import pkgProposal from '../../crystal-smv/ton-packages/Proposal.package';
import pkgPadawan from '../../crystal-smv/ton-packages/Padawan.package';
import pkgProposalFactory from '../../ton-packages/ProposalFactory.package';
import pkgSmvRootStore from '../../crystal-smv/ton-packages/SmvRootStore.package';
import pkgSmvRoot from '../../crystal-smv/ton-packages/SmvRoot.package';
import pkgBftgRootStore from '../../ton-packages/BftgRootStore.package';
import pkgBftgRoot from '../../ton-packages/BftgRoot.package';
import pkgJuryGroup from '../../ton-packages/JuryGroup.package';
import pkgContest from '../../ton-packages/Contest.package';
import {expect} from 'chai';
import {createMultisig, deployDirectly} from '../utils';
import {isAddrActive} from '@rsquad/ton-utils/dist/common';
import {
  callThroughMultisig,
  sendThroughMultisig,
} from '@rsquad/ton-utils/dist/net';
import {EMPTY_ADDRESS} from '@rsquad/ton-utils/dist/constants';
import {utf8ToHex} from '@rsquad/ton-utils/dist/convert';

describe('Create Contest integrative test', () => {
  let client: TonClient;
  let smcSafeMultisigWallet: TonContract;
  let smcBftgRootStore: TonContract;
  let smcBftgRoot: TonContract;
  let smcSmvRootStore: TonContract;
  let smcProposalFactory: TonContract;
  let smcPadawan: TonContract;
  let smcProposal: TonContract;
  let smcSmvRoot: TonContract;

  before(async () => {
    client = createClient();
    smcSafeMultisigWallet = createMultisig(client);

    smcSmvRoot = new TonContract({
      client,
      name: 'SmvRoot',
      tonPackage: pkgSmvRoot,
      keys: await client.crypto.generate_random_sign_keys(),
    });
    await smcSmvRoot.calcAddress();

    smcProposalFactory = await deployDirectly({
      client,
      smcSafeMultisigWallet,
      name: 'ProposalFactory',
      tonPackage: pkgProposalFactory,
      input: {
        addrSmvRoot: smcSmvRoot.address,
      },
    });

    smcSmvRootStore = await deployDirectly({
      client,
      smcSafeMultisigWallet,
      name: 'SmvRootStore',
      tonPackage: pkgSmvRootStore,
    });

    await smcSmvRootStore.call({
      functionName: 'setProposalCode',
      input: await client.boc.get_code_from_tvc({tvc: pkgProposal.image}),
    });

    await smcSmvRootStore.call({
      functionName: 'setPadawanCode',
      input: await client.boc.get_code_from_tvc({tvc: pkgPadawan.image}),
    });

    await smcSmvRootStore.call({
      functionName: 'setProposalFactoryAddr',
      input: {addr: smcProposalFactory.address},
    });

    await sendThroughMultisig({
      smcSafeMultisigWallet,
      dest: smcSmvRoot.address,
      value: 5_000_000_000,
    });
    await smcSmvRoot.deploy({
      input: {addrSmvRootStore: smcSmvRootStore.address},
    });

    console.log(`SmvRoot has been deployed: ${smcSmvRoot.address}`);
    expect(await isAddrActive(client, smcSmvRoot.address)).to.be.true;

    smcBftgRootStore = await deployDirectly({
      client,
      smcSafeMultisigWallet,
      name: '',
      tonPackage: pkgBftgRootStore,
    });

    await smcBftgRootStore.call({
      functionName: 'setJuryGroupCode',
      input: await client.boc.get_code_from_tvc({tvc: pkgJuryGroup.image}),
    });

    await smcBftgRootStore.call({
      functionName: 'setContestCode',
      input: await client.boc.get_code_from_tvc({tvc: pkgContest.image}),
    });

    smcBftgRoot = await deployDirectly({
      client,
      smcSafeMultisigWallet,
      name: 'BftgRoot',
      tonPackage: pkgBftgRoot,
      input: {
        addrBftgRootStore: smcBftgRootStore.address,
      },
    });
    console.log(`smcBftgRoot has been deployed: ${smcBftgRoot.address}`);
  });

  it('deploy Padawan', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: pkgSmvRoot.abi,
      functionName: 'deployPadawan',
      input: {
        addrOwner: smcSafeMultisigWallet.address,
      },
      dest: smcSmvRoot.address,
      value: 3_200_000_000,
    });

    smcPadawan = new TonContract({
      client,
      name: 'Padawan',
      tonPackage: pkgPadawan,
      address: (
        await smcSmvRoot.run({
          functionName: 'resolvePadawan',
          input: {
            addrOwner: smcSafeMultisigWallet.address,
            addrRoot: smcSmvRoot.address,
          },
        })
      ).value.addrPadawan,
    });

    expect(
      await isAddrActive(client, smcPadawan.address),
      `Padawan ${smcPadawan.address} isn't active`,
    ).to.be.true;
  });

  it('deploy Proposal through ProposalFactory', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: pkgProposalFactory.abi,
      functionName: 'deployContestProposal',
      input: {
        client: smcBftgRoot.address,
        title: utf8ToHex('proposal'),
        whiteList: [],
        totalVotes: 10000,
        specific: {
          tags: [utf8ToHex('hello'), utf8ToHex('world')],
          underwayDuration: 100,
          prizePool: 100,
          description: utf8ToHex('description'),
        },
      },
      dest: smcProposalFactory.address,
      value: 3_400_000_000,
    });

    smcProposal = new TonContract({
      client,
      name: 'Proposal',
      tonPackage: pkgProposal,
      address: (
        await smcSmvRoot.run({
          functionName: 'resolveProposal',
          input: {
            addrRoot: smcSmvRoot.address,
            id: 0,
          },
        })
      ).value.addrProposal,
    });

    console.log({
      smcProposalAddress: smcProposal.address,
      smcProposalFactoryAddress: smcProposalFactory.address,
    });

    expect(
      await isAddrActive(client, smcProposal.address),
      `Proposal ${smcProposal.address} isn't active`,
    ).to.be.true;
  });

  it('deposit 10000 votes', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcPadawan.tonPackage.abi,
      functionName: 'deposit',
      input: {
        votes: 10000,
      },
      dest: smcPadawan.address,
      value: 10000 * 1_000_000_000 + 200_000_000,
    });
  });

  it('vote for Proposal with 5010 votes', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: pkgPadawan.abi,
      functionName: 'vote',
      input: {
        addrProposal: smcProposal.address,
        choice: true,
        votes: 5010,
      },
      dest: smcPadawan.address,
      value: 1_500_000_000,
    });
    console.log(smcProposal.address);

    console.log((await smcProposal.run({functionName: '_data'})).value._data);
    console.log(
      (await smcProposal.run({functionName: '_results'})).value._results,
    );

    console.log(
      await smcBftgRoot.run({
        functionName: 'resolveContest',
        input: {addrBftgRoot: smcBftgRoot.address, id: 0},
      }),
    );
  });
});
