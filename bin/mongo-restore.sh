#! /usr/bin/env bash
################################################################################
# mongo-restore.sh                                                             #
################################################################################
#
# Restore a mongo database archive to a mongo instance running in a docker
# container
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

# docker filters to identify the container running the mongodb to restore the database to.
# using the named volume attached to the container has proved to be the most reliable
# way to identify the container
# Listing multiple filters here allows manually editing this script to set the
# filter used to define the MONGO_CONTAINER shell parameter
#
# This should work if executed on the docker node actually running the riffcollector db
# mongo container or w/ an active tunnel to that node.
#  Note: It seems that the ancestor image must be local for it to be recognized ???
#        so I've replaced the ancestor filter: --filter="ancestor=mongo"
#        with the volume filter: --filter="volume=edu-stk_edu-riffcollector-db-data"
VOLUME_FILTER_EDU_PROD="volume=edu-stk_edu-riffcollector-db-data"
VOLUME_FILTER_EDU_DEV="volume=edu-docker_edu-riffcollector-db-data"
VOLUME_FILTER_PFM_PROD="volume=pfm-stk_pfm-riffcollector-db-data"
VOLUME_FILTER_PFM_DEV="volume=riff-docker_pfm-riffcollector-db-data"
VOLUME_FILTER_AD="volume=analyze-data_anl-riffdata-db-data"
MONGO_CNTR_FILTER=$VOLUME_FILTER_EDU_PROD

# default riffcollector mongo database name
DB_NAME_DEFAULT="riff-rawdata"

# default path to the directory where the specified archive should be found
ARCHIVE_PATH_DEFAULT=~/tmp

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
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Restore a mongo database archive to a mongo instance running in a docker container"
    echo
    echo "Syntax: $0 [-h] [-D] [-f <from database>] [-t <to database>] [-d <archive directory>] [-c <container name/id>] <mongodump archive file>"
    echo "options:"
    echo "f     The database name in the archive to be restored. Defaults to '$DB_NAME_DEFAULT'"
    echo "t     The database name to be restored to. Defaults to database name from the archive (-f value)"
    echo "D     Drop target collections before restoring them. Collections not being restored will not be dropped."
    echo "d     The directory where the specified archive is located. Defaults to '$ARCHIVE_PATH_DEFAULT'"
    echo "c     The container name/id which is running the mongo db to restore to."
    echo "      This will override determining the container based on the filter."
    echo "h     Print this Help."
    echo
}

################################################################################
################################################################################
# Process the input options, validate arguments.                               #
################################################################################
# Get the options
MONGO_CONTAINER=$(docker ps --filter="$MONGO_CNTR_FILTER" --filter="status=running" --format={{.Names}})
DB_NAME_FROM=$DB_NAME_DEFAULT
DB_NAME_TO=
ARCHIVE_PATH=$ARCHIVE_PATH_DEFAULT
DROP_OPT=

while getopts ":hDc:f:t:d:" option; do
    case $option in
        c) # The container name/id which is running the mongo db to restore to
            MONGO_CONTAINER=${OPTARG}
            ;;
        f) # The database name in the archive to be restored
            DB_NAME_FROM=${OPTARG}
            ;;
        t) # The database name to be restored to
            DB_NAME_TO=${OPTARG}
            ;;
        d) # The directory where the specified archive is located
            ARCHIVE_PATH=${OPTARG}
            ;;
        D) # Drop the target collections before restoring them, does not drop collections that aren't being restored
            DROP_OPT=--drop
            ;;
        h) # display Help
            Help
            exit -1
            ;;
        \?) # incorrect option
            echo "Error: Invalid option"
            exit -1
            ;;
    esac
done

# Remove the getopts processed options
shift $((OPTIND - 1))

# If a to database name was not specified, use the from database name
if [ -z "$DB_NAME_TO" ]; then
    DB_NAME_TO=$DB_NAME_FROM
fi

# Test validity of and set required arguments
ARCHIVE_NAME="$1"

# check for the existence of the archive
if [[ -z "$ARCHIVE_NAME" || ! -e "${ARCHIVE_PATH}/${ARCHIVE_NAME}" ]]
then
    echo "${RED}ERROR:${RESET}"
    echo "  The backup archive (${BOLD}${CYAN}\"${ARCHIVE_NAME}\"${RESET}) you specified to be restored"
    echo "  doesn't exist in the path ${BOLD}${CYAN}\"${ARCHIVE_PATH}\"${RESET}"
    echo
    Help
    exit -1
fi

################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

echo "The backup archive will be restored using the following:"
echo "  ${BOLD}Mongo container name${RESET}: $MONGO_CONTAINER"
echo "  ${BOLD}Archive file path${RESET}: $ARCHIVE_PATH"
echo "  ${BOLD}Archive file name${RESET}: $ARCHIVE_NAME"
echo "  ${BOLD}Restore database${RESET} $DB_NAME_FROM ${BOLD}to database${RESET} $DB_NAME_TO"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
echo "copy the archive to the mongo container"
docker cp --quiet ${ARCHIVE_PATH}/${ARCHIVE_NAME} ${MONGO_CONTAINER}:/data/
echo "restore the mongo archive"
docker exec -t ${MONGO_CONTAINER} mongorestore --nsInclude="${DB_NAME_FROM}.*" --nsFrom="${DB_NAME_FROM}.*" --nsTo="${DB_NAME_TO}.*" $DROP_OPT --gzip --archive=/data/${ARCHIVE_NAME}

echo "remove the archive from the mongo container"
docker exec -t ${MONGO_CONTAINER} rm /data/${ARCHIVE_NAME}

