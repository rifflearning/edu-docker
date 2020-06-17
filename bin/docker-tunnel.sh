#! /usr/bin/env bash
# This script must not be sourced
#
# Set up the environment to execute local docker commands to a remote
# docker instance.
# Takes 1 argument, the IP that describes the remote machine's network address.
# After this script is sourced: the python environment is activated,
# a tunnel to a remote machine running docker is created and the DOCKER_HOST points at it.

# Quick test to see if this script is being sourced
# https://stackoverflow.com/a/28776166/2184226
(return 0 2>/dev/null) && sourced=1 || sourced=0

if [[ $sourced -ne 0 ]]
then
    echo "This script must not be sourced!"
    return
fi

# Test this is being run from the root of the riff-docker repo working dir
if [[ ! ( -e Makefile && -e bin/docker-swarm.py ) ]]; then
    echo "You do not seem to have sourced this script from the root of the riff-docker working directory."
    echo "Change to the riff-docker working directory and run:"
    echo "  . bin/docker-tunnel <IP>"
    echo
    return
fi

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Start an ssh tunnel for issuing remote docker commands locally"
    echo
    echo "Syntax: $0 [-h] [-u <user>] [-A] <ip address | swarm name if -A>"
    echo "options:"
    echo "A     The argument is an AWS stack name, not an ip address -NOT IMPLEMENTED"
    echo "u     If override the user for the tunnel (if it is not specified in ~/.ssh/config)"
    echo "h     Print this Help."
    echo
}

################################################################################
################################################################################
# Process the input options, validate arguments.                               #
################################################################################
# Get the options
USER=
AWS_CF=
while getopts ":hAu:" option; do
    case $option in
        u) # The user for the remote shell session tunnel
            USER=${OPTARG}
            ;;
        A) # The argument given is a Riff deploy swarm name to use to find the
           # swarm manager of a Cloudformation stack to tunnel to.
            AWS_CF=1
            ;;
        h) # display Help
            Help
            exit -1
            ;;
        \?) # incorrect option
            echo "Error: Invalid option. Run '$0 -h'"
            exit -1
            ;;
    esac
done

# Remove the getopts processed options
shift $((OPTIND - 1))


if [ $# -ne 1 ]; then
    echo "Error: One and only one argument is required. Run '$0 -h'"
    exit -1
fi

REMOTE_IP=$1

source activate
bin/docker-swarm.py start-docker-tunnel $REMOTE_IP
