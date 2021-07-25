import TonContract from './ton-contract';

export const logPubGetter = async (
  str: string,
  smc: TonContract,
  functionName: string,
) =>
  console.log(
    `${str}: ${JSON.stringify(
      (await smc.run({functionName: functionName})).value[functionName],
      null,
      4,
    )}`,
  );

export const logGetter = async (
  str: string,
  smc: TonContract,
  functionName: string,
) =>
  console.log(
    `${str}: ${JSON.stringify(
      (await smc.run({functionName: functionName})).value,
      null,
      4,
    )}`,
  );

export const sleep = ms => {
  return new Promise(resolve => setTimeout(resolve, ms));
};
