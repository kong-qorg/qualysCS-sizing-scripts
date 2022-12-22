# Qualys Container Security AWS License Sizing Script

## Overview
This document describes how to prepare for, and how to run the Qualys Container Security AWS License Sizing Script.

## Prerequisites
### Required Permissions
Use an AWS account with the required permissions to collect sizing information.


#### Required AWS APIs
The below AWS APIs need to be enabled in order to gather information from AWS.
TBD

## Command to scan the AWS EKS clusters and detect the total number of node(s)
./qualyscs_sizing_aws general

## Command to scan the AWS ECR registry and collect images and repositories information
$./qualyscs_sizing_aws registry








