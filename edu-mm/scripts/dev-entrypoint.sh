#!/bin/sh
# This technique of waiting for a docker stop was taken from:
# https://medium.com/@ryan0x44/let-a-docker-container-spin-stop-too-da9206126b38
# NOTE: dash trap didn't recognize SIGTERM, changed it to TERM

RED=`tput -Txterm setaf 1`
RESET=`tput -Txterm sgr0`

echo "${RED}run.sh${RESET} Starting up riff mattermost ..."
cd ~/go/src/github.com/mattermost/mattermost-server
make run-in-container

echo "${RED}run.sh${RESET} Sleeping until terminated..."
# Spin until we receive a SIGTERM (e.g. from `docker stop`)
tail -f /dev/null &
TAIL_PID=${!}
trap 'echo "${RED}run.sh${RESET} Stopping..." ; make stop ; kill $TAIL_PID ; exit 143' TERM # exit = 128 + 15 (SIGTERM)
echo "${RED}run.sh${RESET} tail pid: $TAIL_PID"
wait ${TAIL_PID}
