#!/usr/bin/env bash

read -r -s -p "Cloud Tokens.kdbx password: " password

while true; do
    echo "$password" | terraform plan -out /tmp/i.plan
    echo "$password" | terraform apply /tmp/i.plan
    echo "sleeping"
    sleep 10
done

unset password