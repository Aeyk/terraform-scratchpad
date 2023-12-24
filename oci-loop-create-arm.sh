#!/usr/bin/env bash

read -r -s -p "Cloud Tokens.kdbx password: " password

while true; do
    echo "$password" | terraform plan -out /tmp/i.plan
    echo "$password" | terrraform apply /tmp/i.plan
    sleep
done