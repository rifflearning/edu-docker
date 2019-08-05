#! /usr/bin/env bash
# If given no arguments, all files except *.{gpg,sh} will be encrypted
# to the standard set of recipients.
# If given an argument, that file will be encrypted to the standard set
# of recipients.

glob='*'
if [ $# -eq 1 ]
  then
    glob=$1
fi

declare -a RECIPIENTS=(
        mike@rifflearning.com\
        john@rifflearning.com\
        dan@dcalacci.net\
    )

# Turn the recipient array into a recipient options string
for r in ${RECIPIENTS[*]}; do R_OPTS="${R_OPTS} -r ${r}"; done

for f in $glob
do
    [ -e $f ] || (echo "$f is not a file"; continue)
    [[ $f == *.gpg || $f == *.sh ]] && { echo "ignoring $f"; continue; }
    [[ -f $f.gpg ]] && { echo "already encrypted, delete $f.gpg to encrypt again"; continue; }
    echo -n encrypting $f ...
    gpg2 --encrypt --sign ${R_OPTS} --output $f.gpg $f
    echo done
done
