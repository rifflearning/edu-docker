#! /usr/bin/env bash
#
# Create a backup of the riffdata mongo database running in a docker
# container putting the backup file in ~/tmp.
#
# This should work if sourced on the docker node actually running the riffdata db mongo container
#  Note: It seems that the ancestor image must be local for it to be recognized ???
#        so instead of --filter="ancestor=mongo"
#        so also try --filter="volume=edu-stack_edu-riffdata-db-data"

DEPLOY_SWARM=${DEPLOY_SWARM:-UNKNOWN}
MONGO_CONTAINER=$(docker ps --filter="volume=edu-stk_edu-riffdata-db-data" --filter="status=running" --format={{.Names}})
DATABASE_NAME="riff-test"
TIMESTAMP=$(date +'%Y%m%d%H%M%S')
ARCHIVE_NAME=mongodb_${DATABASE_NAME}.edu.${DEPLOY_SWARM}.backup-${TIMESTAMP}.gz

echo "Backup will be created using the following:"
echo "  Mongo container name: $MONGO_CONTAINER"
echo "  Archive file name: $ARCHIVE_NAME"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
docker exec -t ${MONGO_CONTAINER} mongodump --db=${DATABASE_NAME} --gzip --archive=/data/${ARCHIVE_NAME}
docker exec -t ${MONGO_CONTAINER} ls -lrt /data
docker cp ${MONGO_CONTAINER}:/data/${ARCHIVE_NAME} ~/tmp
docker exec -t ${MONGO_CONTAINER} rm /data/${ARCHIVE_NAME}

