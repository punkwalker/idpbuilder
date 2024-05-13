#! /bin/sh

echo "Starting EC2 Mock agent..."

trap _term SIGTERM

init(){
    export CONFIG_PATH="/root/.ec2-metadata-mock/.aemm-config-used.json"
    echo "Setting up IMDS loopback interface..."
    ifconfig lo:0 169.254.169.254 netmask 255.255.255.255

    echo "Installing AWS CLI..."
    apk --update add aws-cli
    apk --update add jq

    echo "Installing EC2 Mock CLI..."
    wget https://github.com/aws/amazon-ec2-metadata-mock/releases/download/v1.11.2/ec2-metadata-mock-linux-arm64 -O /usr/local/bin/ec2-metadata-mock
    chmod +x /usr/local/bin/ec2-metadata-mock

    echo "Generating EC2 Mock agent config..."
    ec2-metadata-mock -s &> /dev/null &
    kill -TERM $!

    # wget https://raw.githubusercontent.com/slimm609/mock-instance-profile/main/mock_template.json -O mock_template.json

    #static mock values

    export ACCOUNT_ID=$(echo $ROLE_ARN | awk -F ':' '{print $5}')
    export ROLE_NAME=$(echo $ROLE_ARN | awk -F '/' '{print $NF}')
    echo $(jq --arg role_name "$ROLE_NAME" '.metadata.values["iam-security-credentials-role"] |= $role_name' $CONFIG_PATH) > $CONFIG_PATH
    echo $(jq --arg val "/latest/meta-data/iam/security-credentials/$ROLE_NAME" '.metadata.paths["iam-security-credentials"] |= $val' $CONFIG_PATH) > $CONFIG_PATH
    echo $(jq --arg role_arn "$ROLE_ARN" '.metadata.values."iam-info"["InstanceProfileArn"] |= $role_arn' $CONFIG_PATH) > $CONFIG_PATH
}

refresh_credentials(){

    echo "Assuming role and fetching credntials..."
    export LAST_UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # TODO: Add retry if aws command fails
    export $(printf "ACCESS_KEY_ID=%s SECRET_ACCESS_KEY=%s SESSION_TOKEN=%s EXPIRATION=%s" \
        $(aws sts assume-role \
        --role-arn $ROLE_ARN \
        --role-session-name $(hostname) \
        --query "Credentials.[AccessKeyId,SecretAccessKey,SessionToken,Expiration]" \
        --output text))
    export LAST_UPDATED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    echo "Refreshing EC2 Mock assumed role credentials..."

    # Update credntials in config file
    echo $(jq --arg access_key_id "$ACCESS_KEY_ID" '.metadata.values."iam-security-credentials"["AccessKeyId"] |= $access_key_id' $CONFIG_PATH) > $CONFIG_PATH
    echo $(jq --arg secret_access_key "$SECRET_ACCESS_KEY" '.metadata.values."iam-security-credentials"["SecretAccessKey"] |= $secret_access_key' $CONFIG_PATH) > $CONFIG_PATH
    echo $(jq --arg session_token "$SESSION_TOKEN" '.metadata.values."iam-security-credentials"["Token"] |= $session_token' $CONFIG_PATH) > $
    echo $(jq --arg access_key_id "$ACCESS_KEY_ID" '.metadata.values."iam-info"["InstanceProfileId"] |= $access_key_id' $CONFIG_PATH) > $CONFIG_PATH
    echo $(jq --arg expiration "$EXPIRATION" '.metadata.values."iam-security-credentials"["Expiration"] |= $expiration' $CONFIG_PATH) > $CONFIG_PATH
    echo $(jq --arg last_updated "$LAST_UPDATED" '.metadata.values."iam-security-credentials"["LastUpdated"] |= $last_updated' $CONFIG_PATH) > $CONFIG_PATH
    echo $(jq --arg last_updated "$LAST_UPDATED"'.metadata.values."iam-info"["LastUpdated"] |= $last_updated' $CONFIG_PATH) > $CONFIG_PATH

    # Update AccountID in config file
    echo $(jq --arg account_id "$ACCOUNT_ID" '.dynamic.values."instance-identity-document"["accountId"] |= $account_id' $CONFIG_PATH) > $CONFIG_PATH
}

term(){
    echo "Stopping EC2 Mock agent..."
    kill -TERM $MOCK_PID
}

start_mock_loop(){
    while :
    do  
        if ![ -z $MOCK_PID ]; then
            term
        fi
        
        refresh_credentials
        echo "Starting EC2 Mock agent..."
        ec2-metadata-mock -p 80 -n 169.254.169.254 -c $CONFIG_PATH &> /dev/null &
        MOCK_PID=$!

        # Sleep for 3595 (1 hr - 5 seconds) then refresh credentials
        sleep 3595
        wait $!
    done
}

init
start_mock_loop



