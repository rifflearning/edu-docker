#! /usr/bin/env bash
#
# Restore the given ($1) backup of the riffedu mattermost mysql database created
# by the mysql-backup.sh script which uses the mysqldump command to create the
# backup.
# The backup is expected to be found in ~/tmp.
#
# Currently this file SHOULD NOT be executed, it only contains example commands to
# accomplish various backup and restore operations.

# Restore the database of a mattermost mysql database container

MYSQL_CNTR=$(docker ps --filter="volume=edu-stack_edu-mm-db-data" --filter="status=running" --format={{.Names}})
DATABASE_NAME="mattermost_test"
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
echo " mysql container name: $MYSQL_CNTR"
echo "  Archive file path: $ARCHIVE_PATH"
echo "  Archive file name: $ARCHIVE_NAME"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key


# THE ABOVE IS TEST CODE SIMILAR to mongo-restore.sh BUT IS NOT RELEVANT YET TO THE BELOW CODE
#
# THE CODE BELOW CREATES A new named docker volume for the restored mysql database
# then runs a mysql container using that named volume, initializes the empty database, and
# restores the backup to that empty database.


MYSQL_CNTR_NAME=mysql-test
MYSQL_DB_VOL=mysql-test-data
MYSQL_ROOT_PASSWORD=root
ARCHIVE_NAME=mysql.edu.nexted.mm.backup-20190514182232.sql
# Create a volume to attach to a local mysql server container
docker volume create $MYSQL_DB_VOL

# Start and Initialize the mysql server container
docker run -d --name=$MYSQL_CNTR_NAME --publish=3306:3306 --mount="source=$MYSQL_DB_VOL,target=/var/lib/mysql" -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD mysql:5.7

# Restore backup
cat $ARCHIVE_NAME | docker exec -i $MYSQL_CNTR_NAME /usr/bin/mysql --user=root --password=$MYSQL_ROOT_PASSWORD
