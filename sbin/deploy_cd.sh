#!/bin/bash
set -e
tonoscli=../bin/tonos-cli
debot=ContestDebot
debot_abi=../data/$debot.abi.json
debot_tvc=../data/$debot.tvc
debot_keys=../data/$debot.keys.json
giver=0:841288ed3b55d9cdafa806807f02a0ae0c169aa5edfe88a789a6482429756a94
demiurge=0:630394fd1965e72cfc894a2de41f14c35d400d9a96165568ba6ae0a2f1732ef0
store=0:59d0ab618f69905c64cd138d5e700eaa472540447182fa93e8ad8ddabf4d1cfd
function giver {
    $tonoscli call --abi ../data/nse-giver.abi.json $giver sendGrams "{\"dest\":\"$1\",\"amount\":10000000000}"
}
function get_address {
echo $(cat log.log | grep "Raw address:" | cut -d ' ' -f 3)
}

echo GENADDR DEBOT
$tonoscli genaddr $debot_tvc $debot_abi --genkey $debot_keys > log.log
debot_address=$(get_address)
#0:b3da76b95656a5c9de796aefd530b88bc1e3cd682024106e3b9b00b3b2b8c6ec

echo debot address = $debot_address
echo GIVER
giver $debot_address

echo DEPLOY DEBOT
dabi=$(cat $debot_abi | xxd -ps -c 20000)
image=$(cat ../data/JurorContract.tvc | base64 --wrap=0)
$tonoscli deploy $debot_tvc "{\"store\":\"$store\",\"demiurge\":\"$demiurge\",\"jurorWallet\":\"$image\"}" --sign $debot_keys --abi $debot_abi
$tonoscli call $debot_address setABI "{\"dabi\":\"$dabi\"}" --sign $debot_keys --abi $debot_abi
echo DONE
echo ContestDebot address $debot_address

$tonoscli debot fetch $debot_address