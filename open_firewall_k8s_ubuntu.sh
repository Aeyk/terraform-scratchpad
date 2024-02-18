#!/usr/bin/env bash

set -o xtrace 

for port in 6443 2379 2380 10250 10259 10257; do
    sudo iptables -I INPUT 15 -m state --state NEW -p tcp --dport $port -j ACCEPT
done
