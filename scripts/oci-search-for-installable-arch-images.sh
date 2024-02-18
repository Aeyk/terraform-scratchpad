#!/usr/bin/env bash

oci compute image list --compartment-id $oci_compartment_id  --all | jq '.data[]|.id,."display-name"' | grep -e Oracle -e aarch64 -A1

