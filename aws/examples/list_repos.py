import boto3
client = boto3.client('ecr')
response = client.describe_repositories()

