#!/bin/bash
# Install packages
yum update -y
yum install -y jq

# Get EC2 instance info
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .instanceId -r)
REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .region -r)
AZ=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document | jq .availabilityZone -r)

# Create volume from snapshot
VOLUME_ID=$(aws ec2 create-volume \
	--region ${REGION} \
	--availability-zone ${AZ} \
	--snapshot-id snap-0b74a356625a9019a \
	--tag-specifications 'ResourceType=volume,Tags=[{Key=Name,Value=ebs-device}]' \
	--volume-type gp2 \
	--query VolumeId \
	--output text)

# Check if volume is ready
VOLUME_STATE="unknown"
until [ ${VOLUME_STATE} == "available" ]; do
  echo ${VOLUME_STATE}
  VOLUME_STATE=$(aws ec2 describe-volumes \
  	--volume-ids ${VOLUME_ID} \
  	--region ${REGION} \
  	--query Volumes[].State \
	--output text)
  sleep 1s
done

# Attach and mount the EBS volume to this instance
DEVICE='/dev/sdf'
MOUNT_DEVICE='/dev/xvdf'
MOUNT_POINT='/opt/data'

aws ec2 attach-volume --volume-id ${VOLUME_ID} --instance-id ${INSTANCE_ID} --device ${DEVICE} --region ${REGION}

DATA_STATE="unknown"
until [ ${DATA_STATE} == "attached" ]; do
  echo ${DATA_STATE}
  DATA_STATE=$(aws ec2 describe-volumes \
    --region ${REGION} \
    --filters \
        Name=attachment.instance-id,Values=${INSTANCE_ID} \
        Name=attachment.device,Values=${DEVICE} \
    --query Volumes[].Attachments[].State \
    --output text)
  sleep 1s
done
sudo mount ${MOUNT_DEVICE} ${MOUNT_POINT} -t ext4