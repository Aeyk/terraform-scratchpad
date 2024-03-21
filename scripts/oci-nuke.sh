#!/usr/bin/env bash
usage_string="Usage: oci-nuke.sh keepassxc-database
Destroy everything in Oracle inside of ASHBURN-AD-1 and specified tenancy and compartment, searches for the two entries in keepassxc-database under the names 'Oracle Tenancy ID' and 'Oracle Compartment ID'"

## TODO check for keepassxc-cli and jq and die if not exist

if ! test -z "$DEBUG"; then
    debug_oci_string=--debug
fi

if test -z "$1"; then
    echo "$usage_string"
    exit
fi

oci_nuke(){
    oci session authenticate --profile-name DEFAULT --region us-ashburn-1 # TODO check if already signed in
    read -r -s -p "Cloud Tokens.kdbx password: " PASSWORD
    oci_tenancy_id=$(echo "$PASSWORD" | keepassxc-cli show -sa password -q "$1" 'Oracle Tenancy ID')
    oci_compartment_id=$(echo "$PASSWORD" | keepassxc-cli show -sa password -q "$1" 'Oracle Compartment ID')
    oci_compartment_name=$(oci iam compartment get -c "${oci_compartment_id}" --auth security_token | jq  '.data.name')
    # list of region codes where cmpt resources exists
    declare -a region_codes=(
        "IAD"
    )
    echo Compartment being deleted is "${oci_compartment_name}" for ${#region_codes[@]} regions: "${region_codes[@]}"
    for region_code in "${region_codes[@]}"
    do
        unique_stack_id=$(date "+DATE_%Y_%m_%d_TIME_%H_%M") 
        ocid_compartment_stack=$(oci resource-manager stack create-from-compartment --compartment-id "${oci_tenancy_id}" \
                                     --config-source-compartment-id "${oci_compartment_id}" \
                                     --config-source-region "${region_code}" --terraform-version "1.0.x"\
                                     --display-name "Stack_${unique_stack_id}_${region_code}" --description \
                                     "Stack From Compartment ${oci_compartment_name} for region ${region_code}" \
                                     --wait-for-state SUCCEEDED --query "data.resources[0].identifier" \
                                     --raw-output $debug_oci_string --auth security_token)
        echo "$ocid_compartment_stack"
        # twice since it fails sometimes and is idempotent
	      oci resource-manager job create-destroy-job  --execution-plan-strategy 'AUTO_APPROVED'  --stack-id "${ocid_compartment_stack}" --wait-for-state SUCCEEDED --max-wait-seconds 300 $debug_oci_string --auth security_token
       	oci resource-manager job create-destroy-job  --execution-plan-strategy 'AUTO_APPROVED'  --stack-id "${ocid_compartment_stack}" --wait-for-state SUCCEEDED --max-wait-seconds 600 $debug_oci_string --auth security_token
        oci resource-manager stack delete --stack-id "${ocid_compartment_stack}" --force --wait-for-state DELETED $debug_oci_string --auth security_token
    done            
    oci iam compartment delete -c "${oci_compartment_id}" --force --wait-for-state SUCCEEDED $debug_oci_string --auth security_token
}

oci_nuke "$1"
