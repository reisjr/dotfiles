#!/usr/bin/env bash

# FROM https://raw.githubusercontent.com/rhyeal/aws-rotate-iam-keys/master/src/bin/aws-rotate-iam-keys


# Log to syslog if output streams not attached to a terminal (cron, launchd)
if ! test -t 1 && ! test -t 2; then
  exec 1> >(tee >(logger -t $(basename $0))) 2>&1
fi

# Assign the arguments to variables
# saner programming env: these switches turn some bugs into errors
set -eu -o errexit -o pipefail -o noclobber -o nounset
IFS=$'\n\t'

! getopt --test > /dev/null
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    if which brew &> /dev/null && test -d $(brew --prefix)/opt/gnu-getopt/bin; then
        PATH="$(brew --prefix)/opt/gnu-getopt/bin:$PATH"
    else
        echo "I’m sorry, 'getopt --test' failed in this environment."
        exit 1
    fi
fi

# -use ! and PIPESTATUS to get exit code with errexit set
# -temporarily store output to be able to check for errors
# -activate quoting/enhanced mode (e.g. by writing out “--options”)
# -pass arguments only via   -- "$@"   to separate them correctly
! PARSED=$(getopt --options=hvp: --longoptions=profile:,profiles:,version,help --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    # e.g. return value is 1
    #  then getopt has complained about wrong arguments to stdout
    exit 2
fi
# read getopt’s output this way to handle the quoting right:
eval set -- "$PARSED"

PROFILES=""
# now enjoy the options in order and nicely split until we see --
while true; do
    case "$1" in
        --)
          shift
          break
          ;;
        -p|--profiles|--profile)
          PROFILES="$2"
          shift 2
        ;;
        --version|-v)
          echo "AWS Rotate IAM Keys (c) 2018+ Adam Link."
          echo "Licensed under the GNU General Public License."
          echo "Thanks to all the contributors!"
          echo "version <<VERSION>>"
          exit 0
        ;;
        --help|-h)
          echo "To rotate your default profile manually:"
          echo '$ aws-rotate-iam-keys'
          echo ""
          echo "To rotate a specific profile in your ~/.aws/credentials file:"
          echo '$ aws-rotate-iam-keys --profile myProfile'
          echo ""
          echo "To rotate multiple profiles *with the same key*:"
          echo '$ aws-rotate-iam-keys --profiles myProfile,myOtherProfile'
          echo ""
          echo "To rotate multiple profiles *with their own keys*:"
          echo '$ aws-rotate-iam-keys --profile myProfile'
          echo '$ aws-rotate-iam-keys --profile myOtherProfile'
          exit 0
        ;;
    esac
done

# Set the profile to default if nothing sent via CLI
if [[ -z "$PROFILES" ]]; then
    PROFILES=default
fi

set -f; unset IFS             # avoid globbing (expansion of *).
PROFILES_ARR=(${PROFILES//,/ })
FIRST_PROFILE=${PROFILES_ARR[0]}

CURRENT_KEY_ID=$(aws iam list-access-keys --output json --profile $FIRST_PROFILE | jq -r '.AccessKeyMetadata[0].AccessKeyId' || exit 1)

if [[ "$CURRENT_KEY_ID" != "" ]]; then
  # Make a new key
  echo "Making new access key"
  RESPONSE=$(aws iam create-access-key --output json --profile $FIRST_PROFILE | jq .AccessKey)
  ACCESS_KEY=$(echo $RESPONSE | jq -r '.AccessKeyId')
  SECRET=$(echo $RESPONSE | jq -r '.SecretAccessKey')
  if [[ "$ACCESS_KEY" != "" && "$SECRET" != "" ]]; then
    aws iam delete-access-key --access-key-id $CURRENT_KEY_ID --profile ${PROFILES_ARR[0]}

    # Rotate the keys in the credentials file for all profiles
    for i in "${!PROFILES_ARR[@]}"
    do
        echo "Updating profile: ${PROFILES_ARR[i]}"
        aws configure set aws_access_key_id $ACCESS_KEY --profile ${PROFILES_ARR[i]}
        aws configure set aws_secret_access_key $SECRET --profile ${PROFILES_ARR[i]}
    done

    echo "Made new key $ACCESS_KEY"
    echo "Key rotated"
    exit 0
  else
    echo "Could not create access key. Ensure you only have 1 active access key in your IAM profile."
    exit 1
  fi
else
  echo "Could not find current key. Please ensure you have a profile set up using `aws configure`."
  exit 1
fi
