#!/bin/bash
set -e
tonoscli=../bin/tonos-cli
debot=ContestDebot
debot_abi=../data/$debot.abi.json
debot_tvc=../data/$debot.tvc
debot_keys=../data/$debot.keys.json
giver=0:841288ed3b55d9cdafa806807f02a0ae0c169aa5edfe88a789a6482429756a94
demiurge=0:b25a3b44e9280e837011d498d9ea7d9be82a92d93de24cbdb7df43ae73e76b08
store=0:cc0e57456db11f1d56ec9eb90815c0c8546c494113d523853d0dee84498e0200
function giver {
    $tonoscli call --abi ../data/nse-giver.abi.json $giver sendGrams "{\"dest\":\"$1\",\"amount\":10000000000}"
}
function get_address {
echo $(cat log.log | grep "Raw address:" | cut -d ' ' -f 3)
}

echo GENADDR DEBOT
$tonoscli genaddr $debot_tvc $debot_abi --genkey $debot_keys > log.log
debot_address=$(get_address)

echo debot address = $debot_address
echo GIVER
giver $debot_address

echo DEPLOY DEBOT
dabi=$(cat $debot_abi | xxd -ps -c 20000)
image=$(cat ../data/JurorContract.tvc | base64)
$tonoscli deploy $debot_tvc "{\"store\":\"$store\",\"demiurge\":\"$demiurge\",\"jurorWallet\":\"$image\"}" --sign $debot_keys --abi $debot_abi
$tonoscli call $debot_address setABI "{\"dabi\":\"$dabi\"}" --sign $debot_keys --abi $debot_abi
echo DONE
echo ContestDebot address $debot_address

$tonoscli debot --debug fetch $debot_address