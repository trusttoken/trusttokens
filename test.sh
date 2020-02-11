#!/bin/bash
ganache-cli -a 15 -l 0x7a1200 --allowUnlimitedContractSize -k istanbul >/dev/null &
GPID=$!
sleep 1
truffle test $@
kill -15 $GPID
exit
