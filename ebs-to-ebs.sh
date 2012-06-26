#!/bin/bash

# Attaches two EBS volumes and merges them to a third

if [ $# -lt 2 ]
then
  echo
  echo "Usage: ebs-to-ebs.sh vol_id1 vol_id2"
  exit 0
fi  

EBS_VOL1=$1
EBS_VOL2=$2
EC2_INSTANCE_ID="`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`"
EC2_PRIVATE_KEY=~/.aws_creds/pk-SS5MTCPI5NCLXEBYWAXPLRKQJRXWDPW7.pem
EC2_CERT=~/.aws_creds/cert-SS5MTCPI5NCLXEBYWAXPLRKQJRXWDPW7.pem
export EC2_PRIVATE_KEY EC2_CERT

log() {
    # might do something interesting here, but for now it's good for trimming STDOUT
    if [ "$LOGGING" == "false" ]; then
        echo -e $@
    else
        echo -e $@ >> ~/${EC2_INSTANCE_ID}.out
    fi
}

get_ebs_state() {
    vol=`cat ~/ebs-create-log | grep $1 | cut -f 2`
    ec2-describe-volumes $vol | grep $1 | cut -f 6
}

wait_for_ebs() {
    while [ `get_ebs_state $1 | grep $2 | wc -l` -gt 0 ]
    do
        sleep 15
    done
}

attach_volumes() {
    ec2-attach-volume $EBS_VOL1 --instance $EC2_INSTANCE_ID --device /dev/sdf1
    ec2-attach-volume $EBS_VOL2 --instance $EC2_INSTANCE_ID --device /dev/sdf2
}

attach_volume() {
    vol=`cat ~/ebs-create-log | grep VOLUME | cut -f 2`
    ec2-attach-volume $vol --instance $EC2_INSTANCE_ID --device /dev/sdf3
}

create_core() {
    CURL="http://localhost:8983/solr/admin/cores?action=CREATE"
    IDIR="instanceDir=/home/ec2-user/patent-indexing/solr/dir_search_cores/us_patent_grant_v2_0/"
    CFILE="config=solrconfig.xml"
    SFILE="schema=schema.xml"
    DDIR="dataDir=/media/ebs3/data"
    curl "${CURL}&name=${EC2_INSTANCE_ID}&${IDIR}&${CFILE}&${SFILE}&${DDIR}"
}

merge_to_ebs() {
    CURL="http://localhost:8983/solr/admin/cores?action=mergeindexes"
    CORE="core=${EC2_INSTANCE_ID}"
    DIR1="indexDir=/media/ebs1/data/index"
    DIR2="indexDir=/media/ebs2/data/index"
    curl "${CURL}&${CORE}&${DIR1}&${DIR2}"
}

attach_volumes
wait_for_ebs ATTACHMENT attaching

sudo mkdir -p /media/ebs1
sudo mkdir -p /media/ebs2
sudo mount /dev/sdf1 /media/ebs1
sudo mount /dev/sdf2 /media/ebs2

INDEX1_SIZE=`du -s /media/ebs1/data | cut -f 1`
INDEX2_SIZE=`du -s /media/ebs2/data | cut -f 1`
# do some funky math to give us some headway in our new volume
EBS_SIZE=`echo "((${INDEX1_SIZE} + ${INDEX2_SIZE})*3/2000000)+1" | bc`

log "Index1:${INDEX1_SIZE} Index2:${INDEX2_SIZE} EBS:${EBS_SIZE}"

ec2-create-volume --size ${EBS_SIZE} -z us-east-1a >> ~/ebs-create-log
wait_for_ebs VOLUME creating

attach_volume
wait_for_ebs ATTACHMENT attaching

sudo mkfs.ext4 /dev/sdf3
sudo mkdir -p /media/ebs3
sudo mount /dev/sdf3 /media/ebs3
sudo mkdir /media/ebs3/data
sudo chown ec2-user:ec2-user /media/ebs3/data

create_core
merge_to_ebs