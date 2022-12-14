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
  EC2_INSTANCE_COUNT=0
  ECS_FARGATE_TASK_COUNT=0

}
resetGlobalCounters() {
  	EKS_INSTANCE_COUNT_GLOBAL=0
	ECS_INSTANCE_COUNT_GLOBAL=0
	ECS_FARGATE_TASK_COUNT_GLOBAL=0

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
aws_ec2_describe_instances() {
  RESULT=$(aws ec2 describe-instances --max-items 99999 --region="${1}" --filters "Name=instance-state-name,Values=running" --output json 2>/dev/null)
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
aws_ecs_list_clusters() {
  RESULT=$(aws ecs list-clusters --max-items 99999 --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

aws_ecs_list_tasks() {
  RESULT=$(aws ecs list-tasks --max-items 99999 --region "${1}" --cluster "${2}" --desired-status running --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
}

get_ecs_fargate_task_count() {
  REGION=$1
  ECS_FARGATE_CLUSTERS=$(aws_ecs_list_clusters "${REGION}")

  XIFS=$IFS
  # shellcheck disable=SC2206
  IFS=$'\n' ECS_FARGATE_CLUSTERS_LIST=($ECS_FARGATE_CLUSTERS)
  IFS=$XIFS

  ECS_FARGATE_TASK_LIST_COUNT=0
  RESULT=0

  for CLUSTER in "${ECS_FARGATE_CLUSTERS_LIST[@]}"
  do
    ECS_FARGATE_TASK_LIST_COUNT=($(aws_ecs_list_tasks "${REGION}" --cluster "${CLUSTER}" --desired-status running --output json | jq -r '[.taskArns[]] | length' 2>/dev/null))
    RESULT=$((RESULT + ECS_FARGATE_TASK_LIST_COUNT))
  done
  echo "${RESULT}"
}
aws_eks_list_clusters() {
  RESULT=$(aws eks list-clusters --max-items 99999 --region="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
  log "INFO" "aws_eks_list_clusters:  ${RESULT}"
}
#   CLUSTER_OUTPUT=$(aws eks describe-cluster --name=$cluster_name --output json 2>/dev/null)
aws_eks_describe_cluster() {
  RESULT=$(aws eks describe-cluster --name="${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
    exit -1
  fi
  log "INFO" "aws_eks_describe_cluster:  ${RESULT}"
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
    echo "Running EKS Instances"
    for i in "${REGION_LIST[@]}"
    do
      RESOURCE_COUNT="0" # reset
      CLUSTERS_JSON=$(aws_eks_list_clusters "${i}" | jq '.clusters'  2>/dev/null)
      RESOURCE_COUNT=$(echo $CLUSTERS_JSON | jq '. | length' 2>/dev/null)
      echo "  Total # of Running EKS Clusters in Region ${i}: ${RESOURCE_COUNT}"
      EKS_CLUSTER_COUNT=$((EKS_CLUSTER_COUNT + RESOURCE_COUNT))
     
      if  [ ${RESOURCE_COUNT} -ne 0 ]; then # only proceed if resource is not equal zero
	  for row in $(echo $CLUSTERS_JSON | jq -r '.[] '); 
	    do
		# TODO - extract relevant information about the clusters - such as number of nodes, 
		# k8s versions.
       echo "  EKS Clusters in Region ${i} ${$row}"
  
   		cluster_name=$row
    	CLUSTER_OUTPUT=$(aws_eks_describe_cluster "${row}")
    	mkdir -p ./output
	    echo $CLUSTER_OUTPUT > ./output/${row}-cluster-info.json
        # https://docs.aws.amazon.com/cli/latest/reference/eks/describe-cluster.html
        # https://docs.aws.amazon.com/eks/latest/userguide/eks-compute.html
        NODEGROUP_OUTPUT=$(aws eks list-nodegroups --cluster-name=$cluster_name --output json 2>/dev/null)
    	mkdir -p ./output
	    echo $NODEGROUP_OUTPUT > ./output/${row}-nodegroups.json
	  done
      fi
	
    done
    echo "Total EKS Instances across all regions: ${EKS_CLUSTER_COUNT}"
    echo "###################################################################################"
 
    EKS_INSTANCE_COUNT_GLOBAL=${EKS_CLUSTER_COUNT}

    echo "###################################################################################"
    echo "ECS Fargate Tasks"
    for i in "${REGION_LIST[@]}"
    do
       RESOURCE_COUNT=$(get_ecs_fargate_task_count "${i}")
       echo "  Count of Running ECS Tasks in Region ${i}: ${RESOURCE_COUNT}"
       ECS_FARGATE_TASK_COUNT=$((ECS_FARGATE_TASK_COUNT + RESOURCE_COUNT))
    done
    echo "Total ECS Fargate Task Count (Instances) across all regions: ${ECS_FARGATE_TASK_COUNT}"
    echo "###################################################################################"
    echo ""

 
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
echo "Running Qualys Container Security - Sizing tool for AWS "
echo "###################################################################################"

getAccountList
getRegionList
computeResourceSizing

ECS_FARGATE_TASK_COUNT_GLOBAL = $(get_ecs_fargate_task_count)


echo "###################################################################################"
echo "AWS EKS Cluster:"
echo "  Total # of ECS Fargate Task Instances:     ${ECS_FARGATE_TASK_COUNT_GLOBAL}"
echo "  Total # of EKS Instances:     ${EKS_INSTANCE_COUNT_GLOBAL}"

echo ""
echo "###################################################################################"

