#! /usr/bin/env bash
################################################################################
# status.sh                                                                    #
################################################################################
#
# Show the status of this Riff AWS instance
# For a dev instance:
# - Ask if new commits should be fetched for edu-docker and riff-docker
# - Show git status of:
#   - riff-docker
#   - edu-docker
#   - riff-rtc
#   - riff-server
#   - mattermost-server
#   - mattermost-webapp
# - Show current docker images
# - Show stack processes
# - Show running docker containers
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

# docker command formatting
FORMAT_IMAGES="table {{.Repository}}\t{{.Tag}}\t{{.CreatedSince}}"
FORMAT_STACK_PS="table {{.Name}}\t{{.CurrentState}}\t{{.Image}}"
FORMAT_CONTAINER_LS="table {{.Names}}\t{{.Image}}\t{{.Status}}"

# Docker stacks to check for running tasks
DOCKER_STACKS=( support-stack ssl-stack pfm-stk edu-stk )

# Directory containing the Riff repository working directories
RIFF_REPOS=~/riff

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
FETCH=0
EDU_STATUS=0
PFM_STATUS=0
STACK_STATUS=1
CONTAINER_STATUS=0
ASSUME_YES=0

################################################################################
# DefOpt                                                                       #
################################################################################
# Given the name of the flag variable and the on flag and off flag echo the
# flag matching the flag variable value
DefOpt()
{
    local FLAG_VAR=$1
    local FLAG_ON=$2
    local FLAG_OFF=$3
    if (( $FLAG_VAR )); then echo $FLAG_ON; else echo $FLAG_OFF; fi
}

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Show the status of this Riff AWS instance"
    echo
    echo "Syntax: $0 [-h] [-fF] [-eE] [-pP] [-cC] [-sS] [-y]"
    echo "options:"
    echo " f/F  Fetch new commits for riff-docker and edu-docker, ask first. (Def: $(DefOpt FETCH f F))"
    echo " e/E  Show the git status of the Edu (mattermost) working directories. (Def: $(DefOpt EDU_STATUS e E))"
    echo " p/P  Show the git status of the Platform (riff-rtc, riff-server) working directories. (Def: $(DefOpt PFM_STATUS p P))"
    echo " c/C  Show the status of running docker containers. (Def: $(DefOpt CONTAINER_STATUS c C))"
    echo " s/S  Show the status of riff docker stacks with running tasks. (Def: $(DefOpt STACK_STATUS s S))"
    echo " y    Automatic yes to prompts; assume "yes" as answer to all prompts and run non-interactively."
    echo " h    Print this Help."
    echo
    echo "Uppercase options turn off the associated lowercase function. One or the other"
    echo "will be unnecessary depending on the default."
    echo
}

################################################################################
# ParseOptions                                                                 #
################################################################################
ParseOptions()
{
    local OPTIND

    while getopts ":hfFeEpPcCsSy" option; do
        case $option in
            f) # Ask to fetch new commits
                FETCH=1
                ;;
            e) # Show git status of Edu working directories
                EDU_STATUS=1
                ;;
            p) # Show git status of Platform working directories
                PFM_STATUS=1
                ;;
            c) # Show status of running docker containers
                CONTAINER_STATUS=1
                ;;
            s) # Show status of riff docker stacks with running tasks
                STACK_STATUS=1
                ;;
            F) # Do not fetch new commits
                FETCH=1
                ;;
            E) # Do not show git status of Edu working directories
                EDU_STATUS=0
                ;;
            P) # Do not show git status of Platform working directories
                PFM_STATUS=0
                ;;
            C) # Do not show status of running docker containers
                CONTAINER_STATUS=0
                ;;
            S) # Do not show status of riff docker stacks with running tasks
                STACK_STATUS=0
                ;;
            y) # assume "yes" as answer to all prompts
                ASSUME_YES=1
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

    # set the OPTION_ARG_CNT so the caller can shift away the processed options
    # shift $OPTION_ARG_CNT
    let OPTION_ARG_CNT=OPTIND-1
}

################################################################################
# Fetch                                                                        #
################################################################################
Fetch()
{
    local YES=0
    local key
    if (( ASSUME_YES ))
    then
        YES=1
    else
        read -rsp $'Press y to fetch riff-docker and edu-docker: ' -n1 key
        if [ "$key" = "y" ]; then YES=1; echo " yes"; else YES=0; echo " no"; fi
    fi

    if (( YES ))
    then
        pushd $RIFF_REPOS > /dev/null
        if [[ -d riff-docker ]]
        then
            cd riff-docker
            git fetch --prune
            cd ..
        fi
        if [[ -d edu-docker ]]
        then
            cd edu-docker
            git fetch --prune
            cd ..
        fi
        popd > /dev/null
    fi
}

################################################################################
################################################################################
# Process the input options, validate arguments.                               #
################################################################################
ParseOptions "$@"
shift $OPTION_ARG_CNT

# Test validity of and set required arguments
## There are no additional arguments at this time ##

################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

if (( FETCH )); then Fetch; fi

if [[ -d $RIFF_REPOS/edu-docker ]]
then
    pushd $RIFF_REPOS/edu-docker > /dev/null
    echo -n "${WHITE}edu-docker: ${RESET}" ; git status | head -n2
    popd > /dev/null
    SECTION_SPACE=echo
fi

if [[ -d $RIFF_REPOS/riff-docker ]]
then
    pushd $RIFF_REPOS/riff-docker > /dev/null
    $SECTION_SPACE
    echo -n "${WHITE}riff-docker: ${RESET}" ; git status | head -n2
    popd > /dev/null
    SECTION_SPACE=echo
fi

if (( EDU_STATUS ))
then
    pushd $RIFF_REPOS/mattermost-server > /dev/null
    $SECTION_SPACE
    echo -n "${WHITE}mattermost-server: ${RESET}" ; git status | head -n1
    cd ../mattermost-webapp
    echo -n "${WHITE}mattermost-webapp: ${RESET}" ; git status | head -n1
    popd > /dev/null
    SECTION_SPACE=echo
fi

if (( PFM_STATUS ))
then
    pushd $RIFF_REPOS/riff-server > /dev/null
    $SECTION_SPACE
    echo -n "${WHITE}riff-server: ${RESET}" ; git status | head -n1
    cd ../riff-rtc
    echo -n "${WHITE}riff-rtc: ${RESET}" ; git status | head -n1
    popd > /dev/null
    SECTION_SPACE=echo
fi

$SECTION_SPACE
echo "--- ${YELLOW}docker${RESET} ---"
echo "- - - ${YELLOW}IMAGES${RESET} - - -"
docker images --format="$FORMAT_IMAGES"

if (( STACK_STATUS ))
then
    FILTER="desired-state=running"
    for stk in "${DOCKER_STACKS[@]}"
    do
        # Only report on stack processes if some are found
        if docker stack ps --filter="$FILTER" $stk > /dev/null 2>&1
        then
            echo
            echo "- - - ${YELLOW}STACK ($stk) Running Processes${RESET} - - -"
            docker stack ps --filter="$FILTER" --format "$FORMAT_STACK_PS" $stk
        fi
    done
fi

if (( CONTAINER_STATUS ))
then
    echo
    echo "- - - ${YELLOW}Running Containers${RESET} - - -"
    docker container ls --format="$FORMAT_CONTAINER_LS"
fi
