#!/bin/bash
set -e
tonoscli=../bin/tonos-cli
debot=DemiurgeDebot
debot_abi=../data/$debot.abi.json
debot_tvc=../data/$debot.tvc
debot_keys=../data/$debot.keys.json
giver=0:841288ed3b55d9cdafa806807f02a0ae0c169aa5edfe88a789a6482429756a94
target_address=0

price_provider=$(cat ../data/PriceProvider.addr)
function giver {
    $tonoscli call --abi ../data/nse-giver.abi.json $giver sendGrams "{\"dest\":\"$1\",\"amount\":100000000000}"
}
function get_address {
echo $(cat log.log | grep "Raw address:" | cut -d ' ' -f 3)
}

echo GENADDR DEBOT
$tonoscli genaddr $debot_tvc $debot_abi --setkey $debot_keys > log.log
debot_address=$(get_address)

echo debot address = $debot_address
echo GIVER
giver $debot_address

echo DEPLOY DEBOT
dabi=$(cat $debot_abi | xxd -ps -c 20000)
# $tonoscli deploy $debot_tvc "{\"priceProv\":\"$price_provider\"}" --sign $debot_keys --abi $debot_abi
$tonoscli call $debot_address setABI "{\"dabi\":\"$dabi\"}" --sign $debot_keys --abi $debot_abi
echo SETTERS DEBOT
sabi=$(cat ../data/Demiurge.abi.json | xxd -ps -c 20000)
$tonoscli call $debot_address setDemiurgeABI "{\"sabi\":\"$sabi\"}" --sign $debot_keys --abi $debot_abi
sabi=$(cat ../data/VotingDebot.abi.json | xxd -ps -c 20000)
$tonoscli call $debot_address setVotingDebotABI "{\"sabi\":\"$sabi\"}" --sign $debot_keys --abi $debot_abi
sabi=$(cat ../data/Padawan.abi.json | xxd -ps -c 20000)
$tonoscli call $debot_address setPadawanABI "{\"sabi\":\"$sabi\"}" --sign $debot_keys --abi $debot_abi
sabi=$(cat ../data/Proposal.abi.json | xxd -ps -c 20000)
$tonoscli call $debot_address setProposalABI "{\"sabi\":\"$sabi\"}" --sign $debot_keys --abi $debot_abi
si=$(cat ../data/VotingDebot.tvc | base64 )
$tonoscli call $debot_address setVotingDebotImage "{\"image\":\"$si\"}" --sign $debot_keys --abi $debot_abi
si=$(cat ../data/Proposal.tvc | base64 )
$tonoscli call $debot_address setProposalImage "{\"image\":\"$si\"}" --sign $debot_keys --abi $debot_abi
si=$(cat ../data/Padawan.tvc | base64 )
$tonoscli call $debot_address setPadawanImage "{\"image\":\"$si\"}" --sign $debot_keys --abi $debot_abi
si=$(cat ../data/Demiurge.tvc | base64 )
$tonoscli call $debot_address setDemiurgeImage "{\"image\":\"$si\"}" --sign $debot_keys --abi $debot_abi
si=$(cat ../data/Contest.tvc | base64 )
$tonoscli call $debot_address setContestImage "{\"image\":\"$si\"}" --sign $debot_keys --abi $debot_abi
si=$(cat ../data/JuryGroup.tvc | base64 )
$tonoscli call $debot_address setJuryGroupImage "{\"image\":\"$si\"}" --sign $debot_keys --abi $debot_abi
si=$(cat ../data/JurorContract.tvc | base64 )
$tonoscli call $debot_address setJurorImage "{\"image\":\"$si\"}" --sign $debot_keys --abi $debot_abi

echo DONE
echo DemiurgeDebot address $debot_address

$tonoscli debot fetch $debot_address