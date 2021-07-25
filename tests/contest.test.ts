import {TonClient} from '@tonclient/core';
import {createClient} from '../utils/client';
import TonContract from '../utils/ton-contract';
import pkgSafeMultisigWallet from '../ton-packages/SafeMultisigWallet.package';
import pkgBftgRootStore from '../ton-packages/BftgRootStore.package';
import pkgBftgRoot from '../ton-packages/BftgRoot.package';
import pkgJuryGroup from '../ton-packages/JuryGroup.package';
import pkgContest from '../ton-packages/Contest.package';
import {
  hexToBase64,
  utf8ToHex,
  genRandomHex,
  hexToUtf8,
  base64ToHex,
} from '../utils/convert';
import {callThroughMultisig} from '../utils/net';
import {logPubGetter, sleep} from '../utils/common';
import initChunk from './init.chunk';

describe('Contest test', () => {
  let client: TonClient;
  let smcSafeMultisigWallet: TonContract;
  let smcBftgRootStore: TonContract;
  let smcBftgRoot: TonContract;
  let smcContest: TonContract;
  let smcJuryGroup: TonContract;
  let smcSmvRootStore: TonContract;
  let smcSmvRoot: TonContract;
  const pwd = `0x${genRandomHex(64)}`;

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

  it('deploy JuryGroup', async () => {
    console.log(`JuryGroup deploy`);

    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcBftgRoot.tonPackage.abi,
      functionName: 'deployJuryGroup',
      input: {
        tag: utf8ToHex('tag'),
        initialMembers: [process.env.MULTISIG_ADDRESS],
      },
      dest: smcBftgRoot.address,
      value: 500_000_000,
    });

    smcJuryGroup = new TonContract({
      client,
      name: 'JuryGroup',
      tonPackage: pkgJuryGroup,
      address: (
        await smcBftgRoot.run({
          functionName: 'resolveJuryGroup',
          input: {tag: utf8ToHex('tag'), deployer: smcBftgRoot.address},
        })
      ).value.addrJuryGroup,
    });

    console.log(`JuryGroup deployed: ${smcJuryGroup.address}`);

    await logPubGetter('JuryGroup member registered', smcJuryGroup, '_members');
  });

  it('deploy Contest', async () => {
    console.log(`Contest deploy`);

    await smcBftgRoot.call({
      functionName: 'deployContest',
      input: {
        tags: [utf8ToHex('tag'), utf8ToHex('tag2')],
        prizePool: 100_000_000_000,
        underwayDuration: 1000,
      },
    });

    smcContest = new TonContract({
      client,
      name: 'Contest',
      tonPackage: pkgContest,
      address: (
        await smcBftgRoot.run({
          functionName: 'resolveContest',
          input: {deployer: smcBftgRoot.address},
        })
      ).value.addrContest,
    });

    console.log(`Contest deployed: ${smcContest.address}`);

    await logPubGetter('Contest inited', smcContest, '_inited');

    await logPubGetter('Contest tags', smcContest, '_tags');

    await logPubGetter('Contest got jury members', smcContest, '_jury');

    await logPubGetter('Contest stage', smcContest, '_stage');
  });

  it('submit Submission', async () => {
    for (let i = 0; i < 3; i++) {
      await callThroughMultisig({
        client,
        smcSafeMultisigWallet,
        abi: smcContest.tonPackage.abi,
        functionName: 'submit',
        input: {
          addrPartisipant: process.env.MULTISIG_ADDRESS,
          forumLink: utf8ToHex('link'),
          fileLink: utf8ToHex('link'),
          hash: `0x${process.env.MULTISIG_PUBKEY}`,
        },
        dest: smcContest.address,
        value: 500_000_000,
      });
    }

    await logPubGetter('Submission submitted', smcContest, '_submissions');
  });

  it('change stage to Voting', async () => {
    await smcContest.call({functionName: 'changeStage', input: {stage: 3}});

    await logPubGetter('Stage changed', smcContest, '_stage');
  });

  it('vote for Submission', async () => {
    const hiddenVotes = [];

    for (let i = 0; i < 3; i++) {
      const vote = {
        submissionId: i,
        score: 10,
        comment: utf8ToHex('Perfect!'),
      };

      const hashVote = (
        await smcContest.run({
          functionName: 'hashVote',
          input: {
            ...vote,
          },
        })
      ).value.hash;

      const hiddenScore = (
        await client.crypto.chacha20({
          data: hexToBase64('10'),
          key: pwd,
          nonce: '000000000000000000000000',
        })
      ).data;

      const hiddenComment = (
        await client.crypto.chacha20({
          data: hexToBase64(vote.comment),
          key: pwd,
          nonce: '000000000000000000000000',
        })
      ).data;

      hiddenVotes.push({
        submissionId: i,
        hash: hashVote,
        hiddenComment: utf8ToHex(hiddenComment),
        hiddenScore: utf8ToHex(hiddenScore),
      });
    }
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcContest.tonPackage.abi,
      functionName: 'vote',
      input: {
        hiddenVotes,
      },
      dest: smcContest.address,
      value: 10_000_000_000,
    });

    await logPubGetter('vote accepted', smcContest, '_juryHiddenVotes');
  });

  it('change stage to Reveal', async () => {
    await smcContest.call({functionName: 'changeStage', input: {stage: 4}});

    await logPubGetter('Stage changed', smcContest, '_stage');
  });

  it('reveal votes', async () => {
    const encryptedVotes = (
      await smcContest.run({
        functionName: 'getHiddenVotesByAddress',
        input: {
          juryAddr: process.env.MULTISIG_ADDRESS,
        },
      })
    ).value.hiddenVotes;

    const promisesScore = [];
    const promisesComment = [];
    const decryptedVotes = [];

    Object.keys(encryptedVotes).forEach(async key => {
      const encryptedVote = encryptedVotes[key];
      const decryptedVote: {
        score: string;
        comment: string;
        submissionId: number;
      } = {
        score: encryptedVote.hiddenScore,
        comment: encryptedVote.hiddenComment,
        submissionId: encryptedVote.submissionId,
      };
      decryptedVotes.push(decryptedVote);
    });

    decryptedVotes.forEach(async decryptedVote => {
      promisesScore.push(
        client.crypto.chacha20({
          data: hexToUtf8(decryptedVote.score),
          key: pwd,
          nonce: '000000000000000000000000',
        }),
      );
      promisesComment.push(
        client.crypto.chacha20({
          data: hexToUtf8(decryptedVote.comment),
          key: pwd,
          nonce: '000000000000000000000000',
        }),
      );
    });

    (await Promise.all(promisesScore)).forEach(({data}, i) => {
      decryptedVotes[i].score = base64ToHex(data);
    });

    (await Promise.all(promisesComment)).forEach(({data}, i) => {
      decryptedVotes[i].comment = base64ToHex(data);
    });

    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcContest.tonPackage.abi,
      functionName: 'reveal',
      input: {
        revealVotes: decryptedVotes,
      },
      dest: smcContest.address,
      value: 10_000_000_000,
    });

    await logPubGetter('vote revealed', smcContest, '_submissionVotes');
  });

  it('change stage to Rank', async () => {
    await smcContest.call({functionName: 'changeStage', input: {stage: 5}});

    await logPubGetter('Stage changed', smcContest, '_stage');
  });

  it('calc rank votes', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcContest.tonPackage.abi,
      functionName: 'calcRewards',
      input: {},
      dest: smcContest.address,
      value: 10_000_000_000,
    });

    await logPubGetter('Rewards calculated', smcContest, '_rewards');
  });

  it('change stage to Reward', async () => {
    await logPubGetter('Stage changed', smcContest, '_stage');
  });

  it('claim reward', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcContest.tonPackage.abi,
      functionName: 'claimPartisipantReward',
      input: {
        amount: 1_000_000_000,
      },
      dest: smcContest.address,
      value: 200_000_000,
    });

    await logPubGetter('Rewards claimed', smcContest, '_rewards');
  });

  it('stake reward to existed jury group', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcContest.tonPackage.abi,
      functionName: 'stakePartisipantReward',
      input: {
        amount: 1_000_000_000,
        tag: utf8ToHex('tag'),
        addrJury: process.env.MULTISIG_ADDRESS,
      },
      dest: smcContest.address,
      value: 200_000_000,
    });

    await logPubGetter('Rewards staked', smcContest, '_rewards');
    await logPubGetter('JuryGroup members updated', smcJuryGroup, '_members');
  });

  it('stake reward to unexisted jury group', async () => {
    await callThroughMultisig({
      client,
      smcSafeMultisigWallet,
      abi: smcContest.tonPackage.abi,
      functionName: 'stakePartisipantReward',
      input: {
        amount: 1_000_000_000,
        tag: utf8ToHex('tag2'),
        addrJury: process.env.MULTISIG_ADDRESS,
      },
      dest: smcContest.address,
      value: 500_000_000,
    });

    const smcJuryGroup2 = new TonContract({
      client,
      name: 'JuryGroup',
      tonPackage: pkgJuryGroup,
      address: (
        await smcBftgRoot.run({
          functionName: 'resolveJuryGroup',
          input: {tag: utf8ToHex('tag2'), deployer: smcBftgRoot.address},
        })
      ).value.addrJuryGroup,
    });

    await sleep(1000);

    await logPubGetter('Rewards staked', smcContest, '_rewards');

    console.log(`JuryGroup2 deployed: ${smcJuryGroup2.address}`);

    await logPubGetter('JuryGroup2 members updated', smcJuryGroup2, '_members');
  });
});
