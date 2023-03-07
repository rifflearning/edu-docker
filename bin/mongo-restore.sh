#! /usr/bin/env bash
#
# Restore the given ($1) backup of the riffdata mongo database running in
# a docker container. The backup is expected to be found in ~/tmp.
#
# This should work if executed on the docker node actually running the riffdata db
# mongo container or w/ an active tunnel to that node.
#  Note: It seems that the ancestor image must be local for it to be recognized ???
#        so I've replaced the ancestor filter: --filter="ancestor=mongo"
#        with the volume filter: --filter="volume=edu-stk_edu-riffdata-db-data"

VOLUME_FILTER_PROD="volume=edu-stk_edu-riffdata-db-data"
VOLUME_FILTER_DEV="volume=edu-docker_edu-riffdata-db-data"
MONGO_CONTAINER=$(docker ps --filter=$VOLUME_FILTER_PROD --filter="status=running" --format={{.Names}})
DATABASE_NAME="riff-test"
ARCHIVE_PATH=~/tmp
ARCHIVE_NAME=$1

# check for the existence of the archive
if [[ -z "$ARCHIVE_NAME" || ! -e "${ARCHIVE_PATH}/${ARCHIVE_NAME}" ]]
then
    echo "The backup (\"${ARCHIVE_NAME}\") you specified to be restored"
    echo "doesn't exist in the path \"${ARCHIVE_PATH}\""
    return
    exit 1
fi

echo "Backup will be restored using the following:"
echo "  Mongo container name: $MONGO_CONTAINER"
echo "  Archive file path: $ARCHIVE_PATH"
echo "  Archive file name: $ARCHIVE_NAME"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
echo "copy the archive to the mongo container"
docker cp --quiet ${ARCHIVE_PATH}/${ARCHIVE_NAME} ${MONGO_CONTAINER}:/data/
echo "restore the mongo archive"
docker exec -t ${MONGO_CONTAINER} mongorestore --db=${DATABASE_NAME} --gzip --archive=/data/${ARCHIVE_NAME}
echo "remove the archive from the mongo container"
docker exec -t ${MONGO_CONTAINER} rm /data/${ARCHIVE_NAME}

