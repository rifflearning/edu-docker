#! /usr/bin/env bash
################################################################################
# mm-mysql-cli.sh                                                              #
################################################################################
#
# Exec the mysql cli in the running edu-stk mysql container
#
# docker exec -it edu-stk_edu-mm-db.1.rkpsomtdlt5ajzcq7eyelhve4 mysql --user=mmuser --password=mostest
# SHOW databases;
# USE mattermost_test;
#
# To see any non lti users (may include some lti users if they have additional props)
# And then the SQL to clear all existing props from a particular user
# SELECT Username, Email, Props FROM Users WHERE Props NOT LIKE '{"lti%';
# UPDATE Users SET Props = '{}' WHERE Username = 'juliah_esme';
#
# To see users whose username starts with a particular string
# And then the SQL to change the username of a user w/ a particular email
# SELECT Username, Email, Props FROM Users WHERE Username LIKE 'mik%';
# UPDATE Users SET Username = 'mike_lippert' WHERE Email = 'mike@riffanalytics.ai';
#
# To see the survey data (well 10 entries):
# SELECT PValue FROM PluginKeyValueStore WHERE PluginId = 'ai.riffanalytics.survey' LIMIT 10;
#
# Saving to a text file (must use path specified by 'SELECT @@secure_file_priv;')
# SELECT PValue FROM PluginKeyValueStore WHERE PluginId = 'ai.riffanalytics.survey' INTO OUTFILE '/var/lib/mysql-files/survey.out';

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

# edu or AD
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
VOLUME_FILTER_AD_PROD="volume=analyze-data_anl-mm-db-data"
RIFF_APP_VOL_FILTER=VOLUME_FILTER_${RIFF_APP}_PROD
MYSQL_CNTR_FILTER=${!RIFF_APP_VOL_FILTER}

# default mattermost mysql user/password
MYSQL_USER_DEFAULT=mmuser
MYSQL_PSWD_DEFAULT=mostest


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

################################################################################
# Help                                                                         #
################################################################################
Help()
{
    # Display Help
    echo "Start the mysql CLI in a running MySQL DB docker container"
    echo
    echo "Syntax: $0 [-h] [-s] [-u <mysql user name>] [-p <mysql user password>] [-c <container name/id>]"
    echo "options:"
    echo "u     The MySQL user name to use to connect. Defaults to '$MYSQL_USER_DEFAULT'"
    echo "p     The MySQL user password to use to connect. Defaults to '$MYSQL_PSWD_DEFAULT'"
    echo "c     The container name/id which is running the mongo db to restore to."
    echo "      This will override determining the container based on the filter."
    echo "s     Print the SQL command help and exit w/o starting the mysql cli."
    echo "h     Print this Help."
    echo
}

################################################################################
# MM_SQL_Help                                                                  #
################################################################################
MM_SQL_Help()
{
    # Display Help for mysql cli commands for the Mattermost db
    cat - <<- EOF
	### Commands to determine what databases are available, use a database see the tables, see the fields in a table
	  SHOW databases;
	  USE mattermost_test;
	  SHOW tables;
	  DESCRIBE Users;

	### To see any non lti users (may include some lti users if they have additional props)
	  And then the SQL to clear all existing props from a particular user
	  SELECT Username, Email, Props FROM Users WHERE Props NOT LIKE '{"lti%';
	  UPDATE Users SET Props = '{}' WHERE Username = 'juliah_esme';

	### To see users whose username starts with a particular string
	### And then the SQL to change the username of a user w/ a particular email
	  SELECT Username, Email, Props FROM Users WHERE Username LIKE 'mik%';
	  UPDATE Users SET Username = 'mike_lippert' WHERE Email = 'mike@riffanalytics.ai';

	### To see the survey data (well 10 entries):
	  SELECT PValue FROM PluginKeyValueStore WHERE PluginId = 'ai.riffanalytics.survey' LIMIT 10;

	### Saving to a text file (must use path specified by 'SELECT @@secure_file_priv;')
	### And have started the mysql cli w/ the root user
	  SELECT PValue FROM PluginKeyValueStore WHERE PluginId = 'ai.riffanalytics.survey' INTO OUTFILE '/var/lib/mysql-files/survey.out';

	EOF
}

################################################################################
# ParseOptions                                                                 #
################################################################################
ParseOptions()
{
    local OPTIND

    while getopts ":hsc:u:p:" option; do
        case $option in
            c) # The container name/id which is running the mysql db start the cli in
                MYSQL_CONTAINER=${OPTARG}
                ;;
            u) # The mysql user to use to connect
                MYSQL_USER=${OPTARG}
                ;;
            p) # The mysql user's password to use to connect
                MYSQL_PSWD=${OPTARG}
                ;;
            s) # display SQL command help
                MM_SQL_Help
                exit 0
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


################################################################################
################################################################################
# Main program                                                                 #
################################################################################
################################################################################

echo "The MySQL CLI will be run using the following:"
echo "  ${BOLD}MySQL container name${RESET}: $MYSQL_CONTAINER"
read -rsp $'Press any key to continue or Ctrl-C to abort\n' -n1 key

echo
docker exec -it $MYSQL_CONTAINER mysql --user=$MYSQL_USER --password=$MYSQL_PSWD
