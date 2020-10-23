#! /usr/bin/env bash
#
# Create a logical backup of the riffedu mattermost mysql database running in a docker
# container putting the backup file in ~/tmp.
#
# Pay careful attention to the container name and archive name before allowing this
# script to continue.

# Backup the database of a mattermost mysql database container

DEPLOY_SWARM=${DEPLOY_SWARM:-UNKNOWN}
# MYSQL_CNTR=edu-stack_edu-mm-db.1.jxno77rp82lq53v574keg8kv7
MYSQL_CNTR=$(docker ps --filter="volume=edu-stk_edu-mm-db-data" --filter="status=running" --format={{.Names}})
TIMESTAMP=$(date +'%Y%m%d%H%M%S')
ARCHIVE_NAME=mysql.edu.${DEPLOY_SWARM}.mm.backup-${TIMESTAMP}.sql

echo "Backup will be created using the following:"
echo "  mysql container name: $MYSQL_CNTR"
echo "  Archive file name: $ARCHIVE_NAME"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
docker exec $MYSQL_CNTR /usr/bin/mysqldump --user=mmuser --password=mostest --no-tablespaces --databases mattermost_test > ~/tmp/$ARCHIVE_NAME
gzip -9 ~/tmp/$ARCHIVE_NAME

echo "Backup was created in ~/tmp"
ls -la ~/tmp/mysql.*.gz
