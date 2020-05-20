#! /usr/bin/env bash
# show the status of what's on this AWS riffedu instance

cd ~/riff/edu-docker
echo "--- edu-docker ---"
git show --oneline --no-patch

echo
echo "--- docker ---"
echo "- - - IMAGES - - -"
docker images

FORMAT="table {{.Name}}\t{{.CurrentState}}\t{{.Image}}"
FILTER="desired-state=running"
STACKS=( support-stack ssl-stack edu-stk )
for stk in "${STACKS[@]}"
do
    # Only report on stack processes if some are found
    if docker stack ps --filter="$FILTER" $stk > /dev/null 2>&1
    then
        echo
        echo "- - - STACK ($stk) Running Processes - - -"
        docker stack ps --filter="$FILTER" --format "$FORMAT" $stk
    fi
done
