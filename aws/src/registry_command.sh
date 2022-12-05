#!/bin/bash

##########################################################################################
## Use of jq is required by this script.
##########################################################################################

if ! type "jq" > /dev/null; then
  echo "Error: jq not installed or not in execution path, jq is required for script execution."
  exit 1
fi

##########################################################################################
## Set or reset counters.
##########################################################################################
resetAccountCounters() {
  ECR_REPO_COUNT_GLOBAL=0
}
resetGlobalCounters() {
  	ECR_REPO_COUNT_GLOBAL=0
	USE_AWS_ORG=false
}



##########################################################################################
##  Utility functions.
##########################################################################################
getAccountList() {
  if [ "${USE_AWS_ORG}" = "true" ]; then
    echo "###################################################################################"
    echo "Querying AWS Organization"
    MASTER_ACCOUNT_ID=$(aws_organizations_describe_organization | jq -r '.Organization.MasterAccountId' 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "${MASTER_ACCOUNT_ID}" ]; then
      logErrorExit "Error: Failed to describe AWS Organization, check aws cli setup, and access to the AWS Organizations API."
    fi
    # Save current environment variables of the master account.
    MASTER_AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
    MASTER_AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
    MASTER_AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN
    #
    ACCOUNT_LIST=$(aws_organizations_list_accounts)
    if [ $? -ne 0 ] || [ -z "${ACCOUNT_LIST}" ]; then
      error_and_exit "Error: Failed to list AWS Organization accounts, check aws cli setup, and access to the AWS Organizations API."
    fi
    TOTAL_ACCOUNTS=$(echo "${ACCOUNT_LIST}" | jq '.Accounts | length' 2>/dev/null)
    echo "  Total number of member accounts: ${TOTAL_ACCOUNTS}"
    echo "###################################################################################"
    echo ""
  else
    MASTER_ACCOUNT_ID=""
    ACCOUNT_LIST=""
    TOTAL_ACCOUNTS=1
  fi
}

getRegionList() {

  REGIONS=$(aws_ec2_describe_regions | jq -r '.Regions[] | .RegionName' 2>/dev/null | sort)

  XIFS=$IFS
  # shellcheck disable=SC2206
  IFS=$'\n' REGION_LIST=($REGIONS)
  IFS=$XIFS

  if [ ${#REGION_LIST[@]} -eq 0 ]; then
    echo "  Warning: Using default region list"
    REGION_LIST=(us-east-1 us-east-2 us-west-1 us-west-2 ap-south-1 ap-northeast-1 ap-northeast-2 ap-southeast-1 ap-southeast-2 eu-north-1 eu-central-1 eu-west-1 sa-east-1 eu-west-2 eu-west-3 ca-central-1)
  fi
  echo "###################################################################################"
  echo "  Total number of regions: ${#REGION_LIST[@]}"
  echo "###################################################################################"
  echo ""
}
##########################################################################################
## Utility functions.
##########################################################################################
logErrorExit() {
  echo
  echo "ERROR: ${1}"
  echo
  exit 1
}

aws_organizations_describe_organization() {
  RESULT=$(aws organizations describe-organization --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

aws_organizations_list_accounts() {
  RESULT=$(aws organizations list-accounts --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}

aws_sts_assume_role() {
  RESULT=$(aws sts assume-role --role-arn="${1}" --role-session-name=pcs-sizing-script --duration-seconds=999 --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}
aws_ecr_describe_repositories() {
# aws ecr describe-repositories | jq '.repositories[].repositoryName' | sed s/\"//g
  RESULT=$(aws ecr describe-repositories  --region="${1}" | jq '.repositories[].repositoryName' | sed s/\"//g 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}
aws_ec2_describe_regions() {
  RESULT=$(aws ec2 describe-regions --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}
##########################################################################################
## Main
##########################################################################################
computeResourceSizing(){
  resetAccountCounters
  resetGlobalCounters

   for ((ACCOUNT_INDEX=0; ACCOUNT_INDEX<=(TOTAL_ACCOUNTS-1); ACCOUNT_INDEX++))
  do
    if [ "${USE_AWS_ORG}" = "true" ]; then
      ACCOUNT_NAME=$(echo "${ACCOUNT_LIST}" | jq -r .Accounts["${ACCOUNT_INDEX}"].Name 2>/dev/null)
      ACCOUNT_ID=$(echo "${ACCOUNT_LIST}"   | jq -r .Accounts["${ACCOUNT_INDEX}"].Id   2>/dev/null)
      ASSUME_ROLE_ERROR=""
      assume_role "${ACCOUNT_NAME}" "${ACCOUNT_ID}"
      if [ -n "${ASSUME_ROLE_ERROR}" ]; then
        continue
      fi
    fi

    echo "###################################################################################"
    echo "Detecting AWS ECR"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT="0" # reset
      CLUSTERS_JSON=$(aws_ecr_describe_repositories "${i}"  2>/dev/null)
      RESOURCE_COUNT=$(echo $CLUSTERS_JSON | jq '. | length' 2>/dev/null)
      echo "  Total # of ECR repositories in Region ${i}: ${RESOURCE_COUNT}"
      # EKS_CLUSTER_COUNT=$((EKS_CLUSTER_COUNT + RESOURCE_COUNT))
     
      # if  [ $((RESOURCE_COUNT)) -ne 0 ]; then # only proceed if resource is not equal zero
	  # for row in $(echo $CLUSTERS_JSON | jq -r '.[] '); 
	  #   do
	# 	# TODO - extract relevant information about the clusters - such as number of nodes, 
	# 	# k8s versions.
   	# 	cluster_name=$row
    # 	CLUSTER_OUTPUT=$(aws eks describe-cluster --name=$cluster_name --output json 2>/dev/null)
    # 	mkdir -p ./output
	  #   echo $CLUSTER_OUTPUT > ./output/${row}-cluster-info.json
      #   # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-cluster.html
      #   # https://docs.aws.amazon.com/eks/latest/userguide/eks-compute.html
      #   NODEGROUP_OUTPUT=$(aws eks list-nodegroups --cluster-name=$cluster_name --output json 2>/dev/null)
    # 	mkdir -p ./output
	  #   echo $NODEGROUP_OUTPUT > ./output/${row}-nodegroups.json
	  # done
     ## fi
	
    done
    echo "Total ECR Instances across all regions: TBD"
    echo "###################################################################################"
 
  
    #reset_account_counters

    if [ "${USE_AWS_ORG}" = "true" ]; then
      unassume_role
    fi
  done



}
##########################################################################################

# echo "# this file is located in 'src/qualyscs_sizing_aws_command.sh'"
# echo "# code for 'qualyscs_sizing_aws qualyscs_sizing_aws' goes here"
# echo "# you can edit it freely and regenerate (it will not be overwritten)"
# inspect_args
#ECS_FARGATE_CLUSTERS=$(aws_ecs_list_clusters "${REGION}")
#EKS_INSTANCE_COUNT_GLOBAL=$(aws_eks_list_clusters "${REGION}")

echo "###################################################################################"
echo " Qualys Container Security - Sizing tool for AWS "
echo " For AWS ECR Registry"
echo "###################################################################################"

getAccountList
getRegionList
computeResourceSizing


echo "###################################################################################"
# echo "AWS EKS Cluster:"
# echo "  Total # of ECS Fargate Task Instances:     ${ECS_FARGATE_TASK_COUNT_GLOBAL}"
# echo "  Total # of EKS Instances:     ${EKS_INSTANCE_COUNT_GLOBAL}"

echo ""
echo "###################################################################################"

