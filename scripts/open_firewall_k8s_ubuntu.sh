#!/usr/bin/env bash

set -o xtrace 

sudo iptables -I INPUT  -m multiport   -m state --state NEW -p tcp --dports 6443,2379,2380,10250,10259,10257 -j ACCEPT
