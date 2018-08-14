#!/bin/bash

# Original taken from here:
# https://n2ws.com/blog/how-to-guides/automate-amazon-ec2-instance-backup
# Modified by Mike Chistyakov

# This creates aws snapshots of all machines which have termination protection
# It queries how many volumes machines have and then creates snapshot of every
# volume.
# The snapshot retention period is set below.
# It deletes only snapshots which have "Scheduled_Backup*" as description.


#set -x
#set -e
export PATH=$PATH:/var/task/

### Variables
S3_PATH="s3://"

# Snapshots Retention Period for each volume snapshot
RETENTION=7

# Volume list file will have volume-id:Volume-name format
VOLUMES_LIST=volumes_list_with_ids.txt
SNAPSHOT_INFO=snapshot_info.txt
DATE=`date +%Y-%m-%d`
DATETIME=`date +%Y-%m-%d-%H-%M-%S`
REGION="ap-southeast-2"
SNAP_CREATION=snap_creation
SNAP_DELETION=snap_deletion


#echo "List of Snapshots Creation Status" > $SNAP_CREATION
#echo "List of Snapshots Deletion Status" > $SNAP_DELETION

# Create workdir
mkdir $DATETIME

# Sync S3 bucket
# aws s3 sync ./$DATETIME $S3_PATH

# Change workdir
cd $DATETIME



# Get list of all instances
ALL_INSTANCES=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].InstanceId' --output text)

# Find instances with termination protection ON
for instance in $ALL_INSTANCES
do
   aws ec2 describe-instance-attribute --instance-id $instance --attribute disableApiTermination \
   --query '[InstanceId,DisableApiTermination.Value]' \
   --output text | grep True | sed 's/True//'
done > protected_instances.txt



# Get list of volumes from aws

for instance in $(cat protected_instances.txt)
do
  aws ec2 describe-instances --instance-ids $instance --query \
  'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value,InstanceId,BlockDeviceMappings[*].[DeviceName,Ebs.[VolumeId]]]' \
  --filters "Name=tag:Status,Values=Permanent" --output text | awk 'NR > 1 { printf(":") } {printf "%s",$0 }'
  # Get number of volumes per instance
  VOL_NUM=$(aws ec2 describe-instances --instance-ids $instance --query 'Reservations[*].Instances[*].[length(BlockDeviceMappings[*])]' --output text)
  # Create an entry for each volume
  i=0
  while [ "$i" -lt $VOL_NUM ]
  do
    aws ec2 describe-instances --instance-ids $instance --query \
    'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value,InstanceId,BlockDeviceMappings['"$i"'].[DeviceName,Ebs.[VolumeId]]]' \
    --output text | awk 'NR > 1 { printf(":") } {printf "%s",$0 }'
    echo -e ""
    i=`expr $i + 1`
  done
done > volumes_list_with_ids.txt



#aws ec2 describe-instances --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value,InstanceId,BlockDeviceMappings[*].[DeviceName,Ebs.[VolumeId]]]' \
#--filters "Name=tag:Status,Values=Permanent" --output text | tr '\n' ':'
#echo -e

# Strip out machine IDs and names
#echo "$VOLUMES_LIST_WITH_IDS" | grep vol > volumes_list.txt

# Check whether the volumes list file is available or not?

if [ -f $VOLUMES_LIST ]; then

# Creating Snapshot for each volume using for loop

for VOL_INFO in `cat $VOLUMES_LIST`
do
  # Getting the Volume ID and Volume Name into the Separate Variables.

  VOL_ID=`echo $VOL_INFO | awk -F":" '{print $4}'`
  VOL_NAME=`echo $VOL_INFO | awk -F":" '{print $2 "_" $3}'`
  echo "$VOL_ID"
  echo "$VOL_NAME"
  # Creating the Snapshot of the Volumes with Proper Description.

  DESCRIPTION="Scheduled_Backup_${VOL_NAME}_${DATETIME}"
  echo $DESCRIPTION
  echo "Creating snapshot of $VOL_ID" >> $SNAP_CREATION
  aws ec2 create-snapshot --volume-id $VOL_ID --description "$DESCRIPTION" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Purpose,Value=data-recovery}]' \
  --region $REGION &>> $SNAP_CREATION
done
else
  echo "Volumes list file is not available : $VOLUMES_LIST Exiting."
  exit 1
fi

echo >> $SNAP_CREATION

# Delete snapshots which are X days old.

for VOL_INFO in `cat $VOLUMES_LIST`
do

  # Getting the Volume ID and Volume Name into the Separate Variables.
  VOL_ID=`echo $VOL_INFO | awk -F":" '{print $4}'`
  VOL_NAME=`echo $VOL_INFO | awk -F":" '{print $2 "_" $3}'`


  # Getting the Snapshot details of each volume.
  aws ec2 describe-snapshots --query Snapshots[*].[SnapshotId,VolumeId,Description,StartTime] \
  --output text --filters "Name=status,Values=completed" "Name=volume-id,Values=$VOL_ID" "Name=description,Values=Scheduled_Backup*" | grep -v "$DESCRIPTION" > $SNAPSHOT_INFO

  # Snapshots Retention Period Checking and if it crosses delete them.
  while read SNAP_INFO
  do
    SNAP_ID=`echo $SNAP_INFO | awk '{print $1}'`
    echo $SNAP_ID
    SNAP_DATE=`echo $SNAP_INFO | awk '{print $4}' | awk -F"T" '{print $1}'`
    echo $SNAP_DATE

    # Getting the no.of days difference between a snapshot and present day.

    RETENTION_DIFF=`echo $(($(($(date -d "$DATE" "+%s") - $(date -d "$SNAP_DATE" "+%s"))) / 86400))`
    echo $RETENTION_DIFF

    # Deleting the Snapshots which are older than the Retention Period

    if [ $RETENTION -lt $RETENTION_DIFF ];
    then
    aws ec2 delete-snapshot --snapshot-id $SNAP_ID --region $REGION --output text> snap_del
    echo "Deleting snapshot $SNAP_INFO" >> $SNAP_DELETION
  fi
  done < $SNAPSHOT_INFO
done

echo >> $SNAP_DELETION

# Upload report to S3
# aws s3 cp . $S3_PATH/$DATETIME --recursive

# Print report
cat $SNAP_CREATION
cat $SNAP_DELETION
