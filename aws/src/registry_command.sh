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
     ECR_REPO_COUNT=0
     ECR_IMAGE_COUNT=0
}
resetGlobalCounters() {
  	 ECR_REPO_COUNT_GLOBAL=0
     ECR_IMAGE_COUNT_GLOBAL=0
	   USE_AWS_ORG=false
}



##########################################################################################
##  Utility functions.
##########################################################################################
getAccountList() {
  if [ "${USE_AWS_ORG}" = "true" ]; then
    info "###################################################################################"
    info "Querying AWS Organization"
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
    info "  Total number of member accounts: ${TOTAL_ACCOUNTS}"
    info "###################################################################################"
    info ""
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
  info "###################################################################################"
  info "  Total number of regions: ${#REGION_LIST[@]}"
  info "###################################################################################"
 
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
  #aws ecr describe-repositories --region="${1}" 
#  RESULT=$(aws ecr describe-repositories  --region="${1}" | jq '.repositories[].repositoryName' | sed s/\"//g 2>/dev/null)
  RESULT=$(aws ecr describe-repositories  --region="${1}" | jq  2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  else
    echo '{"Error": [] }'
  fi
   Filelog "Info"  "aws_ecr_describe_repositories:  ${RESULT}"
}
aws_ec2_describe_regions() {
  RESULT=$(aws ec2 describe-regions --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
    echo "${RESULT}"
  fi
}


aws_ecr_list_images() {
  IMAGE_JSON=$(aws ecr list-images --repository-name "${1}" --output json 2>/dev/null)
  if [ $? -eq 0 ]; then
     echo "${IMAGE_JSON}"
  else
    echo '{"Error": [] }'
    exit -1
  fi
}

get_image_count_from_image_json() {

  IMAGE_COUNT=$(jq '.imageIds | length' <<< "${1}" 2>/dev/null)
  if [ $? -eq 0 ]; then
     echo "${IMAGE_COUNT}"
  else
    echo '{"Error": [] }'
    exit -1
  fi
}
get_total_image_count_from_repos() {
  # Set the repository name
  repository_name=${1}
  region=${2}
  FilelogDebug "get_total_image_count_from_repos : ${repository_name}"
  # Initialize the total image count to 0
  total_image_count=0
  
  total_image_count=$(aws ecr list-images --repository-name "$repository_name" --region "$region" --query 'imageIds | length(@)' --output text)
  FilelogDebug "total_image_count : ${total_image_count}"
  FilelogDebug "aws ecr list-images --repository-name "$repository_name" --region "$region" --query 'imageIds | length(@)' --output text"
  echo "${total_image_count}"
}

get_total_size_from_image_json() {



  TOTAL_IMAGE_SIZE=$(jq -s 'add | .[].imageSizeInBytes' <<<"${1}" 2>/dev/null)
  if [ $? -eq 0 ]; then
     echo "${TOTAL_IMAGE_SIZE}"
  else
    echo '{"Error": [] }'
    exit -1
  fi
}
##########################################################################################
## Main
##########################################################################################
computeResourceSizing(){
  resetAccountCounters
  resetGlobalCounters
  TOTAL_REPOS=0
  TOTAL_IMAGES=0

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

    info "Scanning AWS ECR"
    for i in "${REGION_LIST[@]}"
    do
      TOTAL_REPOS=0
  
      REPOS_JSON=$(aws_ecr_describe_repositories "${i}"  2>/dev/null)
  
      if jq -e '. == {"repositories": []}' <<< "$REPOS_JSON" > /dev/null; then
        # JSON matches the expected format
        info "Region: ${i} Repository: none"
        continue
      else
        # JSON does not match the expected format
        info "Region: ${i} Repository: "
        mkdir -p ./output-ecr
        echo $REPOS_JSON > ./output-ecr/${i}-repos.json

        # Use jq to count the number of repositories
        REPOS_NAMES=($(jq -r '.repositories[].repositoryName' <<< "$REPOS_JSON"))
        
        FilelogDebug "REPOS_NAMES : ${REPOS_NAMES}"

          # Iterate over the repository names
          for repository_name in "${REPOS_NAMES[@]}"; do
            
            images_count=$(get_total_image_count_from_repos "${repository_name}" "${i}")
            FilelogDebug "repository_name : ${repository_name}"
            FilelogDebug "images_count : ${images_count}"
            TOTAL_REPOS=$((TOTAL_REPOS + 1))
            TOTAL_IMAGES=$((TOTAL_IMAGES + images_count))
          done
        

        info "  Total # of ECR repositories in Region ${i}: ${TOTAL_IMAGES}"
        info "  Total # of ECR images in Region ${i}: ${TOTAL_IMAGES}"
        
     
      fi
      ECR_IMAGE_COUNT_GLOBAL=$((ECR_IMAGE_COUNT_GLOBAL + TOTAL_IMAGES))
      ECR_REPO_COUNT_GLOBAL=$((ECR_REPO_COUNT_GLOBAL + TOTAL_REPOS)) 
	
    done

    info "###################################################################################"
 
    info "Total ECR Repositories across all regions:   ${ECR_REPO_COUNT_GLOBAL}"
    info "Total ECR Images across all regions:   ${ECR_IMAGE_COUNT_GLOBAL}"
   
    info "###################################################################################"
 
  
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

info "###################################################################################"
info " Qualys Container Security - Sizing tool for AWS "
info " For AWS ECR Registry"
info "###################################################################################"

getAccountList
getRegionList
computeResourceSizing


# echo "AWS EKS Cluster:"
# echo "  Total # of ECS Fargate Task Instances:     ${ECS_FARGATE_TASK_COUNT_GLOBAL}"
# echo "  Total # of EKS Instances:     ${EKS_INSTANCE_COUNT_GLOBAL}"

# echo ""
# echo "###################################################################################"

