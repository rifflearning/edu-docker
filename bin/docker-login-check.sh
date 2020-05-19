#! /usr/bin/env bash
################################################################################
# docker-login-check.sh                                                        #
################################################################################
#
# Test that docker login credentials are set and valid for the given registry
#
# from this [answer](https://stackoverflow.com/a/56069459/2184226) to this
# [question](https://stackoverflow.com/questions/36608467/how-can-i-tell-if-im-logged-in-to-a-private-docker-registry-from-a-script/36636657)
#

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "This script will check if valid login credentials are set for a docker image registry"
    echo
    echo "Syntax: $0 [-h|q] <docker-image-registry>"
    echo "options:"
    echo "h     Print this Help."
    echo "q     Quiet mode, no output, just set the exit code"
    echo
    echo "exit  :  0: logged in; 1 not logged in; 2 internal error test image exists?;"
    echo "codes :  3 internal error unknown message; -1 help displayed or syntax error"
    echo
}

################################################################################
# Log                                                                          #
################################################################################
Log()
{
    # Write to stdout unless QUIET is set
    if [[ ! -v QUIET ]]
    then
        echo $*
    fi
}

################################################################################
################################################################################
# Process the input options, validate arguments.                               #
################################################################################
# Get the options
while getopts ":hq" option; do
    case $option in
        q) # quiet mode
            QUIET=1
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
shift $((OPTIND -1))

# Test validity of and set required arguments
if [[ -z "$1" ]]
then
    Help
    exit -1
fi

################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################
REGISTRY="$1"

msg=$(docker pull ${REGISTRY}/missing:missing 2>&1)
case "$msg" in
    *"requested access to the resource is denied"* | *"pull access denied"*)
        Log "Logged out"
        exit 1
        ;;
    *"manifest unknown"* | *"not found"*)
        Log "Logged in, or read access for anonymous allowed"
        exit 0
        ;;
    *"Pulling from"*)
        Log "Missing image was not so missing after all?"
        exit 2
        ;;
    *)
        Log "Unknown message: $msg"
        exit 3
        ;;
esac

