#!/bin/bash

# Static variables

parameterbasename='/default/base/' # Expected name = /default/base/${resource-type}-${tag}-${id-type}

# Functions - Modular

function list-subnets-all-ids (){
    aws ec2 describe-subnets \
        --query 'Subnets[*].[SubnetId]' \
        --output text
    }

function list-subnets-all-name-tags () {
    aws ec2 describe-subnets \
        --query 'Subnets[*].Tags[?Key==`Name`].Value[]' \
        --output text
}

function describe-subnet-by-tag () {
    aws ec2 describe-subnets \
        --filters Name=tag:Name,Values=$1 \
        --output json
}

function create-new-parameter () {
    aws ssm put-parameter \
    --name $1 \
    --type "String" \
    --value $2 \
    --output text
}

function list-all-vpc-name-tags () {
    aws ec2 describe-vpcs --query 'Vpcs[*].Tags[?Key==`Name`].Value[]' \
        --output text
}

function list-all-cmk-key-aliases () {
    aws kms list-aliases \
        | jq '.Aliases[] | select(.AliasName | contains("aws") |not )'
}

function get-egress-ip () {
    dig -4 +short myip.opendns.com @resolver1.opendns.com.
}

# Functions - Core

function export-subnet-resources () {
    SUBNETLIST=$(list-subnets-all-name-tags)
    for name in $SUBNETLIST;
        do
        # Disassemble metadata from tag
        IFS='_' read -r -a subnettag <<< "$name"
        tagzone=${subnettag[0]}
        tagenv=${subnettag[1]}
        tagaz=${subnettag[2]}    
        # Create store name
        prefix=$tagzone"_"$tagaz 
        parameterprefix=$(echo $prefix | awk '{print tolower($0)}' )
        parametername=$parameterbasename"subnet-$parameterprefix"
        # Capture subnet info
        describesubnet=$(describe-subnet-by-tag $name \
            | jq -c '.Subnets[]| .AvailabilityZone,.AvailabilityZoneId,.AvailableIpAddressCount,.CidrBlock,.SubnetId,.SubnetArn' \
            | sed  's/["]//g')
        compoundvalue=$(echo $describesubnet | sed -e "s/ /,/g")
        # echo "compoundvalue=$compoundvalue"
        IFS=',' read -r -a describedsubnet <<< "$compoundvalue"
        subnetaz=${describedsubnet[0]}
        subnetazid=${describedsubnet[1]}
        subnetavailableipcount=${describedsubnet[2]}
        subnetcidrblock=${describedsubnet[3]}
        subnetid=${describedsubnet[4]}
        subnetarn=${describedsubnet[5]}
        # Put Parameter to Parameter Store
        create-new--parameter $parametername-az $subnetaz
        create-new--parameter $parametername-azid $subnetazid
        create-new--parameter $parametername-availableipcount $subnetavailableipcount
        create-new--parameter $parametername-cidrblock $subnetcidrblock
        create-new--parameter $parametername-id $subnetid
        create-new--parameter $parametername-arn $subnetarn
    done
}

function export-vpc-resources () {
    VPCLIST=$(list-all-vpc-name-tags)
    for name in $VPCLIST
        do 
        # Disassemble metadata from tag
        IFS='_' read -r -a vpctag <<< "$name"
        tagenv=${vpctag[0]}
        tagvpc=${vpctag[1]}
        # Create store name
        prefix=$tagvpc
        echo "Prefix:  $tagvpc"
        parameterprefix=$(echo $prefix | awk '{print tolower($0)}' )
        parametername=$parameterbasename"$parameterprefix"
        # Capture VPC info
        describevpc=$(aws ec2 describe-vpcs --filters Name=tag:Name,Values=$name --query 'Vpcs[*].[VpcId,CidrBlock]' --output text)
        compoundvalue=$(echo $describevpc | sed -e "s/ /,/g")
        IFS=',' read -r -a describedvpc <<< "$compoundvalue"
        vpcid=${describedvpc[0]}
        vpccidrblock=${describedvpc[1]}
        # Put Parameter to Parameter Store
        create-new--parameter $parametername-vpcid $vpcid
        create-new--parameter $parametername-cidrblock $vpccidrblock
    done
}

function export-cmk-resources () {
    KEYLIST=$(list-all-cmk-key-aliases | jq '.TargetKeyId'| sed  's/"//g')
    for keyid in $KEYLIST;
        do
        # Capture KMS CMK Key Data
        keyalias=$(aws kms list-aliases --key-id $keyid --query 'Aliases[].AliasName'  --output text)
        keyarn=$(aws kms describe-key --key-id $keyid --query 'KeyMetadata.Arn' --output text)
        keyname=$(echo $keyalias | sed 's/alias//g' | sed 's|/||g' | sed 's/alias//g' | sed -r 's/.{9}$//' )
        # Create store name
        parameterprefix=$(echo $keyname | awk '{print tolower($0)}' )
        parametername=$parameterbasename"kms-$parameterprefix"
        create-new--parameter $parametername-alias $keyalias
        create-new--parameter $parametername-arn $keyarn
        create-new--parameter $parametername-keyid $keyid
        done
}

function export-loadbalancer-resources () {
    lbarn=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerArn' --output text)
    lbdnsname=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].DNSName' --output text)
    lbname=$(aws elbv2 describe-load-balancers --query 'LoadBalancers[*].LoadBalancerName' --output text)
    # Create store name
    prefix='alb'
    parameterprefix=$(echo $prefix | awk '{print tolower($0)}' )
    parametername=$parameterbasename"elb-$parameterprefix"
    # Put Parameter to Parameter Store
    create-new--parameter $parametername-arn $lbarn
    create-new--parameter $parametername-dnsname $lbdnsname
    create-new--parameter $parametername-lbname $lbname
}

function export-egress-ip () {
    egressip=$(get-egress-ip)
    # Create store name
    prefix='egress-ip'
    parameterprefix=$(echo $prefix | awk '{print tolower($0)}' )
    parametername=$parameterbasename"$parameterprefix"
    # Put Parameter to Parameter Store
    create-new--parameter $parametername $egressip
}

# Script Execution

export-subnet-resources
export-vpc-resources
export-cmk-resources
export-loadbalancer-resources
export-egress-ip

exit 0