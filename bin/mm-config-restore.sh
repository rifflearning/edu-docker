#! /usr/bin/env bash
################################################################################
# mm-config-restore.sh                                                         #
################################################################################
#
# Restore the mattermost config.json in a riffedu mm docker container from a backup
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
MM_CNTR=$(docker ps --filter='name=edu-stk_edu-mm.1' --format '{{.ID}}')
ARCHIVE_PATH=$ARCHIVE_PATH_DEFAULT

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Restore the mattermost config.json in a riffedu mm docker container from a backup"
    echo
    echo "The backup archive will be named:"
    echo "  mm-config.${YELLOW}DEPLOY_SWARM${RESET}_${YELLOW}TIMESTAMP${RESET}.json"
    echo
    echo "Syntax: $0 [-h] [-d <archive directory>] [-c <container name/id>]"
    echo "options:"
    echo "d     The directory where the given config.json archive is located. Defaults to '$ARCHIVE_PATH_DEFAULT'"
    echo "c     The container name/id running mattermost to write the config to."
    echo "      This will override determining the container based on the service name."
    echo "h     Print this Help."
}

################################################################################
# ParseOptions                                                                 #
################################################################################
ParseOptions()
{
    local OPTIND

    while getopts ":hc:d:" option; do
        case $option in
            c) # The container name/id running riffedu mm to read the config from
                MM_CNTR=${OPTARG}
                ;;
            d) # The directory where the backup archive (config.json) is located
                ARCHIVE_PATH=${OPTARG}
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
ARCHIVE_NAME="$1"

# Abort if ARCHIVE_NAME isn't given or ARCHIVE_PATH doesn't exist
if [[ -z "$ARCHIVE_NAME" || ! -e "${ARCHIVE_PATH}" ]]
then
    echo "The backup (\"${ARCHIVE_NAME}\") you specified to be restored"
    echo "doesn't exist in the path \"${ARCHIVE_PATH}\""
    exit 1
fi


################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

echo "The config.json backup will be restored using the following:"
echo "  ${BOLD}RiffEdu MM container${RESET}: $MM_CNTR"
echo "  ${BOLD}Archive file name${RESET}: $ARCHIVE_NAME"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
docker cp "${ARCHIVE_PATH}/${ARCHIVE_NAME}" "${MM_CNTR}:/home/mmuser/riffedu/config/config.json"
