#!/bin/bash

# Unset any previously set AWS environment variables to prevent credential conflicts
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# Load environment variables from the .env file passed as the first argument
if [ -f "$1" ]; then
    # Use xargs to export variables from the .env file
    export $(cat "$1" | xargs)
else
    echo "Error: .env file not found!"
    exit 1
fi

# Ensure cron has correct PATH for msmtp
export PATH=$PATH:/usr/local/bin

# Define backup directory and filename with current date
JOPLIN_EXPORT_DIR="$BACKUP_DIR/joplin_export"
DATE="$(date +"%Y-%m-%d")"
DATE_TIME=$(date "+%Y-%m-%d %H:%M:%S")
BACKUP_FILE="$JOPLIN_EXPORT_DIR/joplin_backup_$DATE.zip"

# Function to send email notifications
send_email() {
    local subject="$1"
    local body="$2"

    # Format email and send using msmtp with password from Vault
    EMAIL="To: $ADDRESS\r\nSubject: $subject\r\nFrom: $ADDRESS\r\n\r\n$body\r\n"
    echo -e $EMAIL | msmtp  --passwordeval="echo $MAIL_BRIDGE_PASS" $ADDRESS
}

# Function to retrieve secrets from Vault
retrieve_cred() {
    echo "$(curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --cacert "$VAULT_CACERT" \
    --cert "$VAULT_CLIENT_CERT" \
    --key "$VAULT_CLIENT_KEY" \
    $VAULT_ADDR/$1 | jq -r "$2")"
}

# Authenticate to Vault using AppRole and retrieve the token
RESPONSE=$(curl \
    --request POST \
    --data "{\"role_id\":\"$VAULT_APPROLE_ROLE_ID\",\"secret_id\":\"$VAULT_APPROLE_SECRET_ID\"}" \
    --cacert "$VAULT_CACERT" \
    --cert "$VAULT_CLIENT_CERT" \
    --key "$VAULT_CLIENT_KEY" \
    $VAULT_ADDR/v1/auth/approle/login)

# Extract the Vault token from the response
VAULT_TOKEN=$(echo $RESPONSE | jq -r '.auth.client_token')  

# If the Vault token retrieval failed, log an error and exit
if [ "$VAULT_TOKEN" == "null" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Failed to authenticate with Vault" >> LOG_FILE
    exit 1
fi

# Retrieve email and AWS credentials from Vault
MAIL_BRIDGE_PASS=$(retrieve_cred "$MAIL_BRIDGE" "$MAIL_BRIDGE_PASS_RAW")
export AWS_ACCESS_KEY_ID=$(retrieve_cred "$S3_ACCESS" "$S3_ACCESS_KEY_RAW")
export AWS_SECRET_ACCESS_KEY=$(retrieve_cred "$S3_ACCESS" "$S3_SECRET_KEY_RAW")

# Assume the necessary IAM role for S3 access and extract temporary credentials
CREDS=$(/usr/local/bin/aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name $SESSION_NAME \
    --query "Credentials" \
    --output json)

TEMP_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.AccessKeyId')
TEMP_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.SecretAccessKey')
TEMP_SESSION_TOKEN=$(echo $CREDS | jq -r '.SessionToken')

# Set temporary AWS credentials for the remainder of the script
export AWS_ACCESS_KEY_ID=$TEMP_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$TEMP_SECRET_ACCESS_KEY
export AWS_SESSION_TOKEN=$TEMP_SESSION_TOKEN

# Ensure the backup directory exists
mkdir -p $JOPLIN_EXPORT_DIR

# Copy the Joplin export file to the backup directory
cp $BACKUP_DIR/default/all_notebooks.jex \
    $JOPLIN_EXPORT_DIR/joplin_backup_$DATE.jex

# Compress the exported Joplin file into a zip archive
zip -r $BACKUP_FILE $JOPLIN_EXPORT_DIR/joplin_backup_$DATE.jex

# Upload the zip backup file to the S3 bucket
/usr/local/bin/aws s3 cp $BACKUP_FILE s3://$BUCKET_NAME --no-progress 

# Check if the S3 upload was successful
if [ $? -ne 0 ]; then
    log_message="$DATE_TIME - Line 100 - Command '# Upload to S3 Bucket -
/usr/local/bin/aws s3 cp $BACKUP_FILE s3://$BUCKET_NAME \
--no-progress' failed."
    echo "$log_message" >> "$LOG_FILE"

    # Send email notification in case of failure
    subject="Error occurred copying backup to S3"
    body="$log_message"
    send_email "$subject" "$body"

    # Exit script due to error
    exit 1
fi

# Log successful upload to the log file
echo "$DATE_TIME - Backup successfully uploaded to S3 bucket." >> $LOG_FILE

# Remove old local backup files (older than 7 days)
find -E $BACKUP_DIR \
    -type f \
    -regex ".*/joplin_backup_.*\.(jex|zip)" \
    -mtime +6 \
    -exec rm {} \;

# Log success or failure of old backup removal
if [ $? -ne 0 ]; then
    echo "$DATE_TIME - Failed to remove old local backups from local drive." \
        >> $LOG_FILE

    subject="Backup Cleanup Failure"
    body="$DATE_TIME - Failed to remove old local backups from local drive."
    send_email "$subject" "$body"
else
    echo "$DATE_TIME - Old local backups successfully removed" >> $LOG_FILE
fi
