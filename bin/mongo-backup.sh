#! /usr/bin/env bash
################################################################################
# mongo-backup.sh                                                              #
################################################################################
#
# Backup the riffdata database running in a mongodb docker container
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

# docker filters to identify the container running the mongodb to backup the
# database from. Using the named volume attached to the container has proved to
# be the most reliable way to identify the container.
# Listing multiple filters here allows manually editing this script to set the
# filter used to define the MONGO_CNTR_FILTER shell parameter
#
# This should work if executed on the docker node actually running the riffdata db
# mongo container or w/ an active tunnel to that node.
#  Note: It seems that the ancestor image must be local for it to be recognized ???
#        so I've replaced the ancestor filter: --filter="ancestor=mongo"
#        with the volume filter: --filter="volume=pfm-stk_pfm-riffdata-db-data"
VOLUME_FILTER_edu_PROD="volume=edu-stk_edu-riffdata-db-data"
VOLUME_FILTER_edu_DEV="volume=edu-docker_edu-riffdata-db-data"
VOLUME_FILTER_pfm_PROD="volume=pfm-stk_pfm-riffdata-db-data"
VOLUME_FILTER_pfm_DEV="volume=riff-docker_pfm-riffdata-db-data"
VOLUME_FILTER_RR_PROD=$VOLUME_FILTER_pfm_PROD
VOLUME_FILTER_AD="volume=analyze-data_anl-riffdata-db-data"
RIFF_APP_VOL_FILTER=VOLUME_FILTER_${RIFF_APP}_PROD
MONGO_CNTR_FILTER=${!RIFF_APP_VOL_FILTER}

# default riffdata mongo database name
DB_NAME_DEFAULT="riff-test"

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
# Command Options and Arguments                                                #
################################################################################
# Initialized to default values
# boolean values (0,1) should be tested using (( ))
MONGO_CONTAINER=$(docker ps --filter="$MONGO_CNTR_FILTER" --filter="status=running" --format={{.Names}})
DB_NAME_FROM=$DB_NAME_DEFAULT
ARCHIVE_PATH=$ARCHIVE_PATH_DEFAULT
ARCHIVE_APP=$RIFF_APP

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Backup the riffdata database from a mongodb instance running in a docker container"
    echo
    echo "The backup archive will be named:"
    echo "  mongodb_${YELLOW}DB_NAME${RESET}.${YELLOW}APP${RESET}.${YELLOW}DEPLOY_SWARM${RESET}.backup-${YELLOW}TIMESTAMP${RESET}.gz"
    echo
    echo "Syntax: $0 [-h] [-f <from database>] [-d <archive directory>] [-c <container name/id>]"
    echo "options:"
    echo "a     The APP name to use in the backup file name. Defaults to '$RIFF_APP'"
    echo "f     The name of the database to be backed up. Defaults to '$DB_NAME_DEFAULT'"
    echo "d     The directory where the archive should be saved. Defaults to '$ARCHIVE_PATH_DEFAULT'"
    echo "c     The container name/id which is running the mongo db to restore to."
    echo "      This will override determining the container based on the filter."
    echo "h     Print this Help."
    echo
    echo "The DEPLOY_SWARM environment variable will be used to name the backup archive."
}

################################################################################
# ParseOptions                                                                 #
################################################################################
ParseOptions()
{
    local OPTIND

    while getopts ":hc:f:d:a:" option; do
        case $option in
            c) # The container name/id which is running the mongo db to restore to
                MONGO_CONTAINER=${OPTARG}
                ;;
            f) # The mongo database name to be backed up
                DB_NAME_FROM=${OPTARG}
                ;;
            d) # The directory where the backup archive will be saved
                ARCHIVE_PATH=${OPTARG}
                ;;
            a) # The APP name to use in the backup file name
                ARCHIVE_APP=${OPTARG}
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

# Abort if DEPLOY_SWARM isn't defined.


# The name of the backup archive that will be created in the ARCHIVE_PATH
DEPLOY_SWARM=${DEPLOY_SWARM:-UNKNOWN}
TIMESTAMP=$(date +'%Y%m%d%H%M%S')
ARCHIVE_NAME=mongodb_${DB_NAME_FROM}.${ARCHIVE_APP}.${DEPLOY_SWARM}.backup-${TIMESTAMP}.gz


################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

echo "The backup will be created using the following:"
echo "  ${BOLD}Mongo container name${RESET}: $MONGO_CONTAINER"
echo "  ${BOLD}Archive file name${RESET}: $ARCHIVE_NAME"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
docker exec -t ${MONGO_CONTAINER} mongodump --db=${DATABASE_NAME} --gzip --archive=/data/${ARCHIVE_NAME}
docker exec -t ${MONGO_CONTAINER} ls -lrt /data
docker cp ${MONGO_CONTAINER}:/data/${ARCHIVE_NAME} ${ARCHIVE_PATH}
docker exec -t ${MONGO_CONTAINER} rm /data/${ARCHIVE_NAME}
