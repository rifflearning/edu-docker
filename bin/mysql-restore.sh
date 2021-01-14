#! /usr/bin/env bash
################################################################################
# mysql-restore.sh                                                             #
################################################################################
#
# Restore the riffedu database running in a mongodb docker container
# Restore a backup of the riffedu mattermost mysql database created
# by the mysql-backup.sh script which uses the mysqldump command to create the
# backup.
#

# Quick test to see if this script is being sourced
# https://stackoverflow.com/a/28776166/2184226
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced -eq 1 ]]
then
    echo "This script must not be sourced!"
    return 1
fi

################################################################################
# Constants                                                                    #
################################################################################

# pfm, edu or RR
RIFF_APP=edu

# docker filters to identify the container running mysql to restore the
# database to. Using the named volume attached to the container has proved to
# be the most reliable way to identify the container.
# Listing multiple filters here allows manually editing this script to set the
# filter used to define the MYSQL_CNTR_FILTER shell parameter
#
# This should work if executed on the docker node actually running the mattermost
# db mysql container or w/ an active tunnel to that node.
#  Note: It seems that the ancestor image must be local for it to be recognized ???
#        so I've replaced the ancestor filter: --filter="ancestor=mysql"
#        with the volume filter: --filter="volume=edu-stk_edu-mm-db-data"
VOLUME_FILTER_edu_PROD="volume=edu-stk_edu-mm-db-data"
VOLUME_FILTER_edu_DEV="volume=edu-docker_edu-mm-db-data"
VOLUME_FILTER_AD="volume=analyze-data_anl-mm-db-data"
RIFF_APP_VOL_FILTER=VOLUME_FILTER_${RIFF_APP}_PROD
MYSQL_CNTR_FILTER=${!RIFF_APP_VOL_FILTER}

# default mattermost mysql user/password
MYSQL_USER_DEFAULT=mmuser
MYSQL_PSWD_DEFAULT=mostest

# default path to the directory where the specified archive should be found
ARCHIVE_DIR_DEFAULT=~/tmp


# parameters for formatting the output to the console
# use like this: echo "Note: ${RED}Highlight this important${RESET} thing."
RESET=`tput -Txterm sgr0`
BOLD=`tput -Txterm bold`
BLACK=`tput -Txterm setaf 0`
RED=`tput -Txterm setaf 1`
GREEN=`tput -Txterm setaf 2`
YELLOW=`tput -Txterm setaf 3`
BLUE=`tput -Txterm setaf 4`
MAGENTA=`tput -Txterm setaf 5`
CYAN=`tput -Txterm setaf 6`
WHITE=`tput -Txterm setaf 7`

################################################################################
# Command Options and Arguments                                                #
################################################################################
# Initialized to default values
# boolean values (0,1) should be tested using (( ))
MYSQL_CONTAINER=$(docker ps --filter="$MYSQL_CNTR_FILTER" --filter="status=running" --format={{.Names}})
MYSQL_USER=$MYSQL_USER_DEFAULT
MYSQL_PSWD=$MYSQL_PSWD_DEFAULT
ARCHIVE_DIR=$ARCHIVE_DIR_DEFAULT

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Restore the given mattermost mysql database archive to a mysql instance running in a docker container"
    echo
    echo "Syntax: $0 [-h] [-u <mysql user name>] [-p <mysql user password>] [-d <archive directory>] [-c <container name/id>] <mysql archive>"
    echo "options:"
    echo "u     The MySQL user name to use to connect. Defaults to '$MYSQL_USER_DEFAULT'"
    echo "p     The MySQL user password to use to connect. Defaults to '$MYSQL_PSWD_DEFAULT'"
    echo "d     The directory where the given archive is located. Defaults to '$ARCHIVE_DIR_DEFAULT'"
    echo "c     The container name/id which is running the mongo db to restore to."
    echo "      This will override determining the container based on the filter."
    echo "h     Print this Help."
    echo
    echo "The given archive is expected to be gzip compressed and created by mysqldump."
}

################################################################################
# ParseOptions                                                                 #
################################################################################
ParseOptions()
{
    local OPTIND

    while getopts ":hc:d:u:p:" option; do
        case $option in
            c) # The container name/id which is running the mysql db to restore to
                MYSQL_CONTAINER=${OPTARG}
                ;;
            d) # The directory where the backup archive will be found
                ARCHIVE_DIR=${OPTARG}
                ;;
            u) # The mysql user to use to connect
                MYSQL_USER=${OPTARG}
                ;;
            p) # The mysql user's password to use to connect
                MYSQL_PSWD=${OPTARG}
                ;;
            h) # display Help
                Help
                exit -1
                ;;
            \?) # incorrect option
                echo "Error: Invalid option. Use -h for help."
                exit -1
                ;;
        esac
    done

    # set the OPTION_ARG_CNT so the caller can shift away the processed options
    # shift $OPTION_ARG_CNT
    let OPTION_ARG_CNT=OPTIND-1
}
################################################################################
################################################################################
# Process the input options, validate arguments.                               #
################################################################################
ParseOptions "$@"
shift $OPTION_ARG_CNT

# Test validity of and set required arguments
## There are no additional arguments at this time ##
ARCHIVE_NAME="$1"

# The path to the backup archive that will be restored
ARCHIVE_PATH="${ARCHIVE_DIR}/${ARCHIVE_NAME}"

# Abort if ARCHIVE_NAME isn't given or ARCHIVE_PATH doesn't exist
if [[ -z "$ARCHIVE_NAME" || ! -e "${ARCHIVE_PATH}" ]]
then
    echo "The backup (\"${ARCHIVE_NAME}\") you specified to be restored"
    echo "doesn't exist in the path \"${ARCHIVE_DIR}\""
    return
    exit 1
fi


################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

echo "The MySQL database will be restored using the following:"
echo "  ${BOLD}MySQL container name${RESET}: $MYSQL_CONTAINER"
echo "  ${BOLD}Archive file name${RESET}: $ARCHIVE_NAME"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
gunzip --stdout "$ARCHIVE_PATH" | docker exec -i $MYSQL_CONTAINER /usr/bin/mysql --user=$MYSQL_USER --password=$MYSQL_PSWD

exit 0

#
# Instead of restoring to a running RiffEdu swarm mysql container perhaps
# we would want to start up a new mysql container and restore there in order to
# examine the database?

# THE CODE BELOW CREATES A new named docker volume for the restored mysql database
# then runs a mysql container using that named volume, initializes the empty database, and
# restores the backup to that empty database.

MYSQL_CNTR_NAME=mysql-test
MYSQL_DB_VOL=mysql-test-data
MYSQL_ROOT_PASSWORD=root

# Create a volume to attach to a local mysql server container
docker volume create $MYSQL_DB_VOL

# Start and Initialize the mysql server container
docker run -d --name=$MYSQL_CNTR_NAME --publish=3306:3306 --mount="source=$MYSQL_DB_VOL,target=/var/lib/mysql" -e MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD mysql:5.7

# Restore backup
gunzip --stdout "$ARCHIVE_PATH" | docker exec -i $MYSQL_CNTR_NAME /usr/bin/mysql --user=root --password=$MYSQL_ROOT_PASSWORD

# Now you can use the following to run the mysql cli and examine the restored DB:
# $ docker exec -it $MYSQL_CNTR_NAME mysql --user=root --password=$MYSQL_ROOT_PASSWORD
# mysql> SHOW databases;
# mysql> USE mattermost_test;
# mysql> DESCRIBE User;
# mysql> SELECT Email, Props FROM User;
