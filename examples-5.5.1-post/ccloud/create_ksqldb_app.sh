#!/bin/bash
Time()
{
export DT=`date +"%H:%M:%S"`
}


#################################################################
# Initialization
#################################################################
# Source library
source ../utils/helper.sh
source ../utils/ccloud_library.sh

#################################################################
# Source CCloud configurations
#################################################################
DELTA_CONFIGS_DIR=delta_configs
source $DELTA_CONFIGS_DIR/env.delta

#################################################################
# Confluent Cloud ksqlDB application
#################################################################
Time
echo ${DT} ====== Verifying prerequisites

echo -e "\n${DT} ===== Confluent Cloud ksqlDB application\n"
ccloud::validate_ksqldb_up "$KSQLDB_ENDPOINT" "$CONFIG_FILE" "$KSQLDB_BASIC_AUTH_USER_INFO" || exit 1

# Create required topics and ACLs
echo -e "${DT} ===== Configure ACLs (Access Control Lists) for topics on Confluent Cloud ksqlDB"
ksqlDBAppId=$(ccloud ksql app list | grep "$KSQLDB_ENDPOINT" | awk '{print $1}')
ccloud ksql app configure-acls $ksqlDBAppId pageviews users USERS_ORIGINAL PAGEVIEWS_FEMALE PAGEVIEWS_FEMALE_LIKE_89 PAGEVIEWS_REGIONS
for topic in USERS_ORIGINAL PAGEVIEWS_FEMALE PAGEVIEWS_FEMALE_LIKE_89 PAGEVIEWS_REGIONS; do
  Time
  echo "${DT} ===== Creating topic $topic and ACL permitting KSQL to write to it"
  ccloud kafka topic create $topic
  ccloud kafka acl create --allow --service-account $(ccloud service-account list | grep $ksqlDBAppId | awk '{print $1;}') --operation WRITE --topic $topic
done

# Submit KSQL queries
Time
echo -e "\n${DT} ===== Submit KSQL queries\n"
properties='"ksql.streams.auto.offset.reset":"earliest","ksql.streams.cache.max.bytes.buffering":"0"'
while read ksqlCmd; do
  echo -e "\n$ksqlCmd\n"
  response=$(curl -X POST $KSQLDB_ENDPOINT/ksql \
       -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
       -u $KSQLDB_BASIC_AUTH_USER_INFO \
       --silent \
       -d @<(cat <<EOF
{
  "ksql": "$ksqlCmd",
  "streamsProperties": {$properties}
}
EOF
))
  echo $response
  if [[ ! "$response" =~ "SUCCESS" ]]; then
    Time
    echo -e "\n${DT} ===== ERROR: KSQL command '$ksqlCmd' did not include \"SUCCESS\" in the response.  Please troubleshoot."
    exit 1
  fi
done <statements.sql

exit 0
