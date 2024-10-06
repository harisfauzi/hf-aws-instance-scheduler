#!/bin/bash

set -eE -o pipefail
ARG_ARRAY=("--no-colour")
AWS_ROLE_TO_ASSUME=FAODeployerRole

# Parse ~/.aws/credentials to get the short term AWS keys given AWS profile name
get_short_term_credentials() {
    AWS_ACCESS_KEY=$(grep -A6 "\[${SHORT_AWS_PROFILE}\]" ~/.aws/credentials | grep aws_access_key_id | awk '{print $NF}')
    AWS_SECRET_KEY=$(grep -A6 "\[${SHORT_AWS_PROFILE}\]" ~/.aws/credentials | grep aws_secret_access_key | awk '{print $NF}')
    AWS_SECURITY_TOKEN=$(grep -A6 "\[${SHORT_AWS_PROFILE}\]" ~/.aws/credentials | grep aws_session_token | awk '{print $NF}')
    AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
    AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
    AWS_SESSION_TOKEN=$AWS_SECURITY_TOKEN
    export AWS_ACCESS_KEY AWS_SECRET_KEY AWS_SECURITY_TOKEN AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}

# Parse ~/.aws/credentials to get the short term AWS keys given AWS profile name
get_long_term_credentials() {
    AWS_ACCESS_KEY=$(grep -A2 "\[${LONG_AWS_PROFILE}\]" ~/.aws/credentials | grep aws_access_key_id | awk '{print $NF}')
    AWS_SECRET_KEY=$(grep -A2 "\[${LONG_AWS_PROFILE}\]" ~/.aws/credentials | grep aws_secret_access_key | awk '{print $NF}')
    AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY
    AWS_SECRET_ACCESS_KEY=$AWS_SECRET_KEY
    export AWS_ACCESS_KEY AWS_SECRET_KEY AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
}

# Get AWS Account ID given the account name, using mapping provided in accounts.json
get_aws_account_id() {
  local aws_account_name=$1
  local account_id
  account_id=$(jq --arg name "${aws_account_name}" -r '.Accounts[] | select(.Name==$name) | .Id' < accounts.json)
  echo "${account_id}"
}

# Switch AWS account by calling aws sts assume-role
assume_role() {
    local aws_account_id
    aws_account_id=$(get_aws_account_id "${AWS_ACCOUNT}")
    echo "Using $aws_account_id AWS Account ID"
    local aws_role_to_assume
    aws_role_to_assume="${AWS_ROLE_TO_ASSUME}"

    local role_arn_to_assume
    role_arn_to_assume="arn:aws:iam::${aws_account_id}:role/${aws_role_to_assume}"
    local identity_session
    identity_session=$(aws sts get-caller-identity | jq -r '.Arn' | awk -F'/' '{print $NF}')
    local role_session_name
    role_session_name="${identity_session}@$(date +%s)"
    local local_profile
    local_profile=()
    if [ -n "${LONG_AWS_PROFILE}" ]; then
      local_profile+=("--profile")
      local_profile+=("${LONG_AWS_PROFILE}")
    fi
    local assumed_credentials
    assumed_credentials=$(aws sts assume-role "${local_profile[@]}" --region us-west-1 \
        --role-arn "${role_arn_to_assume}" \
        --role-session-name "${role_session_name}")

    # Ansible
    AWS_ACCESS_KEY=$(echo "${assumed_credentials}" | jq -r '.Credentials.AccessKeyId')
    AWS_SECRET_KEY=$(echo "${assumed_credentials}" | jq -r '.Credentials.SecretAccessKey')
    AWS_SECURITY_TOKEN=$(echo "${assumed_credentials}" | jq -r '.Credentials.SessionToken')
    export AWS_ACCESS_KEY AWS_SECRET_KEY AWS_SECURITY_TOKEN
    # AWS CLI
    AWS_ACCESS_KEY_ID=$(echo "${assumed_credentials}" | jq -r '.Credentials.AccessKeyId')
    AWS_SECRET_ACCESS_KEY=$(echo "${assumed_credentials}" | jq -r '.Credentials.SecretAccessKey')
    AWS_SESSION_TOKEN=$(echo "${assumed_credentials}" | jq -r '.Credentials.SessionToken')
    export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    echo "Assumed AWS_ACCESS_KEY is $AWS_ACCESS_KEY"
}

# Launch the main call, either sceptre launch, sceptre delete, or sceptre generate
launch() {
    local SCRIPT_ACTION=$1
    local CFN_CONFIG=$2
    local ACTION=()
    cd sceptre/

    if [ "z${SCRIPT_ACTION}" == "zdeploy" ]; then
        ACTION=("launch" "--prune" "-y")
    elif [ "z${SCRIPT_ACTION}" == "zdestroy" ]; then
        ACTION=("delete" "-y")
    elif [ "z${SCRIPT_ACTION}" == "zgenerate" ]; then
        ACTION=("generate")
    else
      echo "Invalid action. You need to define action as"
      echo "$0 -n <action>"
      echo "Where valid actions are choice of deploy, destroy, generate."
    fi

    if [[ "z${DRY_RUN}" == "z" ]] || [[ "z${DRY_RUN}" == "zfalse" ]]; then
        echo "[Calling:]"
        if [[ "${SCRIPT_ACTION}" == "generate" ]] && [[ -n "${GENERATED_FILE}" ]]; then
          echo "sceptre " \
            "${ARG_ARRAY[@]}" "${ACTION[@]}" \
            " ${CFN_CONFIG} | sed 's/\s*$//g' > ${GENERATED_FILE}"
          sceptre \
            "${ARG_ARRAY[@]}" \
            "${ACTION[@]}" "${CFN_CONFIG}" | sed 's/\s*$//g' > "${GENERATED_FILE}"
        else
          echo "sceptre "\
            "${ARG_ARRAY[@]}" "${ACTION[@]}" \
            " ${CFN_CONFIG}"
          sceptre \
            "${ARG_ARRAY[@]}" \
            "${ACTION[@]}" "${CFN_CONFIG}"
        fi
    fi
    EXIT_STATUS=$?
    cd ../
    exit ${EXIT_STATUS}
}

# Parse command line arguments, translate them into usable variables
parse_arguments() {
    while (( "$#" )); do
      case "$1" in
        -a|--account)
          AWS_ACCOUNT=$2
          shift 2
          ;;
        -l|--long-term-profile)
          LONG_AWS_PROFILE=$2
          shift 2
          ;;
        -s|--short-term-profile)
          SHORT_AWS_PROFILE=$2
          shift 2
          ;;
        -e|--extra-vars)
          ARG_ARRAY+=("--var" "${2}")
          shift 2
          ;;
        -f|--var-file)
          ARG_ARRAY+=("--var-file" "./variables/${2}")
          shift 2
          ;;
        -n|--action)
          SCRIPT_ACTION=$2
          shift 2
          ;;
        -i|--item)
          CFN_CONFIG=$2
          shift 2
          ;;
        -g|--generated-file)
          GENERATED_FILE=$2
          shift 2
          ;;
        -d|--dry-run)
          DRY_RUN=$2
          shift 2
          ;;
        --) # end argument parsing
          shift
          break
          ;;
        -*) # unsupported flags
          echo "Error: Unsupported flag $1" >&2
          exit 1
          ;;
        *) # preserve positional arguments
          PARAMS="$PARAMS $1"
          shift
          ;;
      esac
    done
    # set positional arguments in their proper place
    eval set -- "$PARAMS"
}

# main function
main() {

    # SWITCH_ACCOUNT=1
    parse_arguments "$@"
    if [ "z$AWS_ACCOUNT" != "z" ]; then
        # Call assume_role to switch AWS account
        assume_role
    elif [ "z$SHORT_AWS_PROFILE" != "z" ]; then
        get_short_term_credentials
    elif [ "z$LONG_AWS_PROFILE" != "z" ]; then
        get_long_term_credentials
    fi

    launch "${SCRIPT_ACTION}" "${CFN_CONFIG}"
}

main "$@"
