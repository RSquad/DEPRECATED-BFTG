import {TonClient} from '@tonclient/core';
import TonContract from '../utils/ton-contract';
import pkgBftgRootStore from '../ton-packages/BftgRootStore.package';
import pkgBftgRoot from '../ton-packages/BftgRoot.package';
import pkgJuryGroup from '../ton-packages/JuryGroup.package';
import pkgContest from '../ton-packages/Contest.package';
import pkgGroup from '../ton-packages/Group.package';
import pkgProposal from '../../crystal-smv/ton-packages/Proposal.package';
import pkgPadawan from '../../crystal-smv/ton-packages/Padawan.package';
import pkgProposalFactory from '../ton-packages/ProposalFactory.package';
import pkgSmvRootStore from '../../crystal-smv/ton-packages/SmvRootStore.package';
import pkgSmvRoot from '../../crystal-smv/ton-packages/SmvRoot.package';
import {expect} from 'chai';
import {EMPTY_ADDRESS, EMPTY_CODE} from '../utils/constants';
import {logPubGetter} from '../utils/common';
import {deployDirectly} from '../crystal-smv/tests/utils';

export default async (
  client: TonClient,
  smcSafeMultisigWallet: TonContract,
) => {
  let smcBftgRootStore: TonContract;
  let smcBftgRoot: TonContract;
  let smcSmvRootStore: TonContract;
  let smcSmvRoot: TonContract;
  let smcProposalFactory: TonContract;

  let keys = await client.crypto.generate_random_sign_keys();
  smcBftgRootStore = new TonContract({
    client,
    name: 'BftgRootStore',
    tonPackage: pkgBftgRootStore,
    keys,
  });

  await smcBftgRootStore.calcAddress();

  await smcSafeMultisigWallet.call({
    functionName: 'sendTransaction',
    input: {
      dest: smcBftgRootStore.address,
      value: 1_000_000_000,
      bounce: false,
      flags: 1,
      payload: '',
    },
  });

  console.log(`BftgRootStore deploy`);

  await smcBftgRootStore.deploy();

  console.log(`BftgRootStore deployed: ${smcBftgRootStore.address}`);

  console.log(`BftgRootStore set JuryGroup code`);

  await smcBftgRootStore.call({
    functionName: 'setJuryGroupCode',
    input: {
      code: (
        await client.boc.get_code_from_tvc({tvc: pkgJuryGroup.image})
      ).code,
    },
  });

  console.log(`BftgRootStore set Contest code`);

  await smcBftgRootStore.call({
    functionName: 'setContestCode',
    input: {
      code: (await client.boc.get_code_from_tvc({tvc: pkgContest.image})).code,
    },
  });

  let codes = Object.values(
    (await smcBftgRootStore.run({functionName: '_codes'})).value._codes,
  );

  expect(codes).to.have.lengthOf(2);
  codes.forEach(code => {
    expect(code).to.not.be.eq(EMPTY_CODE);
  });

  let addrs = Object.values(
    (await smcBftgRootStore.run({functionName: '_addrs'})).value._addrs,
  );
  expect(addrs).to.have.lengthOf(0);
  addrs.forEach(addr => {
    expect(addr).to.not.be.eq(EMPTY_ADDRESS);
  });

  keys = await client.crypto.generate_random_sign_keys();
  smcBftgRoot = new TonContract({
    client,
    name: 'BftgRoot',
    tonPackage: pkgBftgRoot,
    keys,
  });

  await smcBftgRoot.calcAddress();

  await smcSafeMultisigWallet.call({
    functionName: 'sendTransaction',
    input: {
      dest: smcBftgRoot.address,
      value: 2_000_000_000,
      bounce: false,
      flags: 1,
      payload: '',
    },
  });

  console.log(`BftgRoot deploy`);

  await smcBftgRoot.deploy({
    input: {
      addrBftgRootStore: smcBftgRootStore.address,
    },
  });

  console.log(`BftgRoot deployed: ${smcBftgRoot.address}`);

  await logPubGetter('BftgRoot inited', smcBftgRoot, '_inited');

  keys = await client.crypto.generate_random_sign_keys();
  smcSmvRoot = new TonContract({
    client,
    name: 'SmvRoot',
    tonPackage: pkgSmvRoot,
    keys,
  });

  await smcSmvRoot.calcAddress();

  smcProposalFactory = await deployDirectly({
    client,
    smcSafeMultisigWallet,
    name: '',
    tonPackage: pkgProposalFactory,
    input: {
      addrSmvRoot: smcSmvRoot.address,
    },
  });

  let stored = (await smcBftgRoot.run({functionName: 'getStored'})).value;
  expect(Object.keys(stored)).to.have.lengthOf(2);
  expect(stored.codeContest).to.be.not.eq(EMPTY_CODE);
  expect(stored.codeJuryGroup).to.be.not.eq(EMPTY_CODE);

  keys = await client.crypto.generate_random_sign_keys();
  smcSmvRootStore = new TonContract({
    client,
    name: 'SmvRootStore',
    tonPackage: pkgSmvRootStore,
    keys,
  });

  await smcSmvRootStore.calcAddress();

  await smcSafeMultisigWallet.call({
    functionName: 'sendTransaction',
    input: {
      dest: smcSmvRootStore.address,
      value: 1_000_000_000,
      bounce: false,
      flags: 1,
      payload: '',
    },
  });

  console.log(`SmvRootStore deploy`);

  await smcSmvRootStore.deploy();

  console.log(`SmvRootStore deployed: ${smcSmvRootStore.address}`);

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

  await smcSafeMultisigWallet.call({
    functionName: 'sendTransaction',
    input: {
      dest: smcSmvRoot.address,
      value: 2_000_000_000,
      bounce: false,
      flags: 1,
      payload: '',
    },
  });

  console.log(`SmvRoot deploy`);

  await smcSmvRoot.deploy({
    input: {
      addrSmvRootStore: smcSmvRootStore.address,
    },
  });

  console.log(`SmvRoot deployed: ${smcSmvRoot.address}`);

  await logPubGetter('SmvRoot inited', smcSmvRoot, '_inited');

  return {
    smcBftgRootStore,
    smcBftgRoot,
    smcSmvRootStore,
    smcSmvRoot,
  };
};
