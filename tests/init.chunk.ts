import {TonClient} from '@tonclient/core';
import TonContract from '../utils/ton-contract';
import pkgBftgRootStore from '../ton-packages/BftgRootStore.package';
import pkgBftgRoot from '../ton-packages/BftgRoot.package';
import pkgJuryGroup from '../ton-packages/JuryGroup.package';
import pkgContest from '../ton-packages/Contest.package';
import pkgPadawan from '../ton-packages/Padawan.package';
import pkgProposal from '../ton-packages/Proposal.package';
import pkgGroup from '../ton-packages/Group.package';
import pkgProposalFactory from '../ton-packages/ProposalFactory.package';
import pkgSmvRoot from '../ton-packages/SmvRoot.package';
import pkgSmvRootStore from '../ton-packages/SmvRootStore.package';
import {expect} from 'chai';
import {EMPTY_ADDRESS, EMPTY_CODE} from '../utils/constants';
import {logPubGetter} from '../utils/common';

export default async (
  client: TonClient,
  smcSafeMultisigWallet: TonContract,
) => {
  let smcBftgRootStore: TonContract;
  let smcBftgRoot: TonContract;
  let smcSmvRootStore: TonContract;
  let smcSmvRoot: TonContract;

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

  console.log(`SmvRootStore set Padawan code`);

  await smcSmvRootStore.call({
    functionName: 'setPadawanCode',
    input: {
      code: (await client.boc.get_code_from_tvc({tvc: pkgPadawan.image})).code,
    },
  });

  console.log(`SmvRootStore set Proposal code`);

  await smcSmvRootStore.call({
    functionName: 'setProposalCode',
    input: {
      code: (await client.boc.get_code_from_tvc({tvc: pkgProposal.image})).code,
    },
  });

  console.log(`SmvRootStore set Group code`);

  await smcSmvRootStore.call({
    functionName: 'setGroupCode',
    input: {
      code: (await client.boc.get_code_from_tvc({tvc: pkgGroup.image})).code,
    },
  });

  console.log(`SmvRootStore set ProposalFactory code`);

  await smcSmvRootStore.call({
    functionName: 'setProposalFactoryCode',
    input: {
      code: (
        await client.boc.get_code_from_tvc({tvc: pkgProposalFactory.image})
      ).code,
    },
  });

  console.log(`SmvRootStore set BftgRoot address`);

  await smcSmvRootStore.call({
    functionName: 'setBftgRootAddr',
    input: {
      addr: smcBftgRoot.address,
    },
  });

  codes = Object.values(
    (await smcSmvRootStore.run({functionName: '_codes'})).value._codes,
  );
  expect(codes).to.have.lengthOf(4);
  codes.forEach(code => {
    expect(code).to.not.be.eq(EMPTY_CODE);
  });

  addrs = Object.values(
    (await smcSmvRootStore.run({functionName: '_addrs'})).value._addrs,
  );
  expect(addrs).to.have.lengthOf(1);
  addrs.forEach(addr => {
    expect(addr).to.not.be.eq(EMPTY_ADDRESS);
  });

  keys = await client.crypto.generate_random_sign_keys();
  smcSmvRoot = new TonContract({
    client,
    name: 'SmvRoot',
    tonPackage: pkgSmvRoot,
    keys,
  });

  await smcSmvRoot.calcAddress();

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

  stored = (await smcSmvRoot.run({functionName: 'getStored'})).value;
  expect(Object.keys(stored)).to.have.lengthOf(6);
  expect(stored.codePadawan).to.be.not.eq(EMPTY_CODE);
  expect(stored.codeProposal).to.be.not.eq(EMPTY_CODE);
  expect(stored.codeGroup).to.be.not.eq(EMPTY_CODE);
  expect(stored.codeProposalFactory).to.be.not.eq(EMPTY_CODE);
  expect(stored.addrBftgRoot).to.be.not.eq(EMPTY_ADDRESS);
  expect(stored.addrProposalFactory).to.be.not.eq(EMPTY_ADDRESS);

  return {
    smcBftgRootStore,
    smcBftgRoot,
    smcSmvRootStore,
    smcSmvRoot,
  };
};
