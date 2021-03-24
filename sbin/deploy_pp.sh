#!/bin/bash
set -e

tonoscli=../bin/tonos-cli
contract=../data/PriceProvider
giver=0:841288ed3b55d9cdafa806807f02a0ae0c169aa5edfe88a789a6482429756a94
function giver {
    $tonoscli call --abi ../data/nse-giver.abi.json $giver sendGrams "{\"dest\":\"$1\",\"amount\":100000000000}"
}
function get_address {
echo $(cat log.log | grep "Raw address:" | cut -d ' ' -f 3)
}

$tonoscli genaddr $contract.tvc $contract.abi.json --genkey $contract.keys.json > log.log
contract_address=$(get_address)
echo GIVER
giver $contract_address

$tonoscli deploy $contract.tvc "{}" --sign $contract.keys.json --abi $contract.abi.json
echo DONE

echo price provider address = $contract_address
echo $contract_address > ../data/$contract.addr