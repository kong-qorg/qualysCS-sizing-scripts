import boto3
import re


def get_latest_master_image():
    """ Filter images with prefix master- and return the latest pushed one """
    client = boto3.client('ecr', region_name='ap-southeast-1')
    response = client.list_images(
        registryId='111111111111',
        repositoryName='repo/application',
        maxResults=1000
    )

    latest = None
    temp_tag = None

    for image in response['imageIds']:
        tag = image['imageTag']
        if re.search("^master-[0-9]+", tag):
            img = client.describe_images(
                registryId='111111111111',
                repositoryName='repo/application',
                imageIds=[
                    {
                        'imageTag': tag
                    },
                ]
            )
            pushed_at = img['imageDetails'][0]['imagePushedAt']
            if latest is None:
                latest = pushed_at
            else:
                if latest < pushed_at:
                    latest = pushed_at
                    temp_tag = tag
    return temp_tag, latest


version, pushed_at = get_latest_master_image()
print(f'app {version} pushed at {pushed_at}')
