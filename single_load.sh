#!/bin/bash

if [ $# -lt 1 ]
then
  echo
  echo "Usage: single_load.sh patent_grant_url"
  exit 0
fi  

START=$(date +%s)
EC2_INSTANCE_ID="`wget -q -O - http://169.254.169.254/latest/meta-data/instance-id`"
SCRIPT_DIR=${SCRIPT_DIR:-~/patent-indexing}
SOLR_XML=${SCRIPT_DIR}/solr/dir_search_cores/solr.xml

# Unzip categories.zip if necessary
if [ ! -f ${SCRIPT_DIR}/categories.xml ] ; then
    pushd ${SCRIPT_DIR}
    unzip categories.zip
    popd
fi

url=$1
data_dir=/media/ebs/data

file=`echo ${url} | awk -F '/' '{print $7}'`
filebase=`echo ${file} | awk -F '.' '{print $1}'`
test ! -d $filebase && mkdir $filebase
ln -s ${SCRIPT_DIR}/categories.xml ${filebase}/categories.xml
ln -s ${SCRIPT_DIR}/saxon9he.jar ${filebase}/saxon9he.jar
ln -s ${SCRIPT_DIR}/convert.xsl ${filebase}/convert.xsl
ln -s ${SCRIPT_DIR}/cals_table.xsl ${filebase}/cals_table.xsl
(
    cd $filebase
    
    # Pull down the file if needed
    if [ ! -f $file ]
    then
        wget -q ${url} -o wget.log
        ${SCRIPT_DIR}/fix-zip-filenames.sh
        #echo ${file}
        ZIP_SIZE=`du -h ${file} | cut -f 1`
        unzip ${file}
    fi

    # Do transformation if needed
    if [ ! -f ${filebase}.json ]
    then
        ${SCRIPT_DIR}/convert.sh ${filebase}.xml ${filebase}.json >> ~/${EC2_INSTANCE_ID}.${filebase}.convert.log 2>&1
    fi
    
    # Create core if needed
    if [ "1" != `grep -c ${filebase} $SOLR_XML` ]
    then
        CURL="http://localhost:8983/solr/admin/cores?action=CREATE"
        IDIR="instanceDir=/home/ec2-user/patent-indexing/solr/dir_search_cores/us_patent_grant_v2_0/"
        CFILE="config=solrconfig.xml"
        SFILE="schema=schema.xml"
        DDIR="dataDir=${data_dir}"
        curl "${CURL}&name=${filebase}&${IDIR}&${CFILE}&${SFILE}&${DDIR}"
    fi
    
    INDEX_SIZE=`du -sh ${data_dir} | cut -f 1`
    (export SOLR_CORE=${filebase}; ${SCRIPT_DIR}/post_json.sh ${filebase}.json >> ~/${EC2_INSTANCE_ID}.${filebase}.post.log 2>&1)
    #####rm -f ${file}.json ${filebase}.xml ${file}

    END=$(date +%s)
    DIFF=$(( $END - $START ))

    echo -e "${EC2_INSTANCE_ID}\t${file}\t${ZIP_SIZE}\t${INDEX_SIZE}\t${DIFF}" >> ~/${EC2_INSTANCE_ID}.out
    #	Ordinal
)
