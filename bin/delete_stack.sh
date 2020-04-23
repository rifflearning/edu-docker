#! /usr/bin/env bash
# This script will delete a known deployed Riff Edu docker swarm from AWS by
# deleting it's associated AWS cloudformation stack and wait for it to be deleted

# Quick test to see if this script is being sourced (it does not have to be)
# https://stackoverflow.com/a/28776166/2184226
(return 0 2>/dev/null) && sourced=1 || sourced=0

# Show help if no argument is given
if [[ -z "$1" ]]
then
    echo "This script will delete the AWS cloudformation stack that was deployed for"
    echo "a 'known' Riff Edu docker swarm."
    echo
    echo "It should be run from the root of the edu-docker working directory"
    echo '  bin/delete_stack.sh <known swarm name defined in bin/aws_stack_vars>'
    echo
    if [[ $sourced -ne 1 ]] ; then exit 1 ; fi
    return 1
fi

# Check that it is run from the expected location
if [[ ! -e bin/internal/create_aws_stack_w_args ]]; then
    echo "You do not seem to have run this script from the root of the riff-docker working directory."
    echo "Change to the edu-docker working directory and run:"
    echo "  bin/delete_stack.sh <swarm name>"
    echo
    if [[ $sourced -ne 1 ]] ; then exit 2 ; fi
    return 2
fi

# Set the AWS stack variables (the stack suffix and the region, keypair maps) and the
# derived variables for '$1' (DEPLOY_SWARM, AWS_CF_STACK_NAME, AWS_STACK_REGION, AWS_STACK_KEYPAIR)
source bin/aws_stack_vars $1

# Check that $1 was a known swarm name
if [[ -z "$DEPLOY_SWARM" ]]
then
    echo "'$1' is not a known Riff Edu swarm name. It must be one of:"
    echo "  ${SWARM_NAMES[@]}"
    echo
    if [[ $sourced -ne 1 ]] ; then exit 3 ; fi
    return 3
fi

# We're in the right CWD but we still need to be able to activate the python 3 virtual environment so check for it
if [[ ! -e activate ]]; then
    echo "The activate script must exist in the CWD, is the python3 virtual environment"
    echo "configured (docs/python-setup.md)?"
    echo
    if [[ $sourced -ne 1 ]] ; then exit 4 ; fi
    return 4
fi

source activate

REGION_OPT=${AWS_STACK_REGION:+"--region=$AWS_STACK_REGION"}

echo
echo Deleting the $AWS_CF_STACK_NAME cloudformation stack in AWS${AWS_STACK_REGION:+" ($AWS_STACK_REGION)"}:
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key
echo

date

echo bin/docker-swarm.py delete $REGION_OPT $AWS_CF_STACK_NAME
bin/docker-swarm.py delete $REGION_OPT $AWS_CF_STACK_NAME
RC=$?
if [[ $RC -ne 0 ]]; then
    if [[ $sourced -ne 1 ]] ; then exit 5 ; fi
    return 5
fi

echo
echo "Wait for the deletion of the CloudFormation stack to complete."
echo "The status will be checked and reported every minute until it is"
echo "complete (10-20 min)"
echo
echo bin/docker-swarm.py wait-for-complete $REGION_OPT $AWS_CF_STACK_NAME
bin/docker-swarm.py wait-for-complete $REGION_OPT $AWS_CF_STACK_NAME

echo
date
