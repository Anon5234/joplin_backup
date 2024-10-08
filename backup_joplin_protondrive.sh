#!/bin/bash

# SEE IF I CAN PASS THE ENV FILE AS AN ENV VAR IN THE CALL TO THE FUNCTION.
# TO AVOID INCLUDING MY ACTUAL FILE LOCATION IN GIT.

# Load the .env file
source /Users/garretmurray/Projects/JoplinBackup/.env

# For debugging purposes, write available environment variables to env_output.log
env > /Users/garretmurray/JoplinBackup/env_output.log

# Ensure cron has correct path to msmtp
export PATH=$PATH:/usr/local/bin

# Define the function to send an email
send_email() {
    local subject="$1"
    local body="$2"

    EMAIL="To: $ADDRESS\r\nSubject: $subject\r\nFrom: $ADDRESS\r\n\r\n$body\r\n"
    echo -e $EMAIL | msmtp $ADDRESS
}

# Authenticate to vault and retrieve the token
RESPONSE=$(curl \
    --request POST \
    --data "{\"role_id\":\"$VAULT_APPROLE_ROLE_ID\",\"secret_id\":\"$VAULT_APPROLE_SECRET_ID\"}" \
    --cacert "$VAULT_CACERT" \
    --cert "$VAULT_CLIENT_CERT" \
    --key "$VAULT_CLIENT_KEY" \
    $VAULT_ADDR/v1/auth/approle/login)

VAULT_TOKEN=$(echo $RESPONSE | jq -r '.auth.client_token')  

# Check if token retrieval was successful
if [ "$VAULT_TOKEN" == "null" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Failed to authenticate with Vault"
    exit 1
fi

# Retrieve the mail-bridge password
MAIL_BRIDGE_PASS=$(curl --header "X-Vault-Token: $VAULT_TOKEN" \
    --cacert "$VAULT_CACERT" \
    --cert "$VAULT_CLIENT_CERT" \
    --key "$VAULT_CLIENT_KEY" \
    $VAULT_ADDR/$MAIL_BRIDGE | jq -r '.data.data.data.value')


# Define backup variables
JOPLIN_EXPORT_DIR="$BACKUP_DIR/joplin_export"
DATE=$(date +"%Y-%m-%d")
DATE_TIME=$(date "+%Y-%m-%d %H:%M:%S")
BACKUP_FILE="$JOPLIN_EXPORT_DIR/joplin_backup_$DATE.zip"
LOG_FILE="/var/log/joplin_backup_script.log"
PROTON_BACKUP="$PROTON_DRIVE_DIR/joplin_backup_$DATE.zip"

# Step 1: Ensure the export directory exists
mkdir -p $JOPLIN_EXPORT_DIR

# Step 2: Copy the Joplin backup to the export directory
cp $BACKUP_DIR/default/all_notebooks.jex $JOPLIN_EXPORT_DIR/joplin_backup_$DATE.jex

# Step 3: Compress the export
zip -r $BACKUP_FILE $JOPLIN_EXPORT_DIR/joplin_backup_$DATE.jex

# Step 4: Upload to Proton Drive
cp $BACKUP_FILE $PROTON_DRIVE_DIR

# Step 5: Check if the upload was successful
if [ $? -eq 0 ]; then
    echo "$DATE_TIME - Backup successfully uploaded to Proton Drive." \
        >> $LOG_FILE

    # Step 6: Remove local old backups (older than 7 days)
    # find -E $BACKUP_DIR -type f -regex ".*/joplin_backup_.*\.(jex|zip)" -mtime +1 -exec rm {} \;

    # Debug find command (if modified more than a minute ago):
    find -E $BACKUP_DIR \
        -type f \
        -regex ".*/joplin_backup_.*\.(jex|zip)" \
        -mmin +1 \
        -exec rm {} \;

    if [ $? -eq 0 ]; then
        echo "$DATE_TIME - Old local backups removed successfully from " \
            "joplin_export folder and backup successfully uploaded to Proton Drive." \
            >> $LOG_FILE
        
        # Send email on success
        subject="Successful Backup of Joplin to Proton Drive"
        body="Backup and cleanup completed successfully on $DATE_TIME."
        send_email "$subject" "$body"

    else
        echo "$DATE_TIME - Failed to remove old local backups for local drive." >> $LOG_FILE

        subject="Backup Cleanup Failure"
        body="Failed to remove old local backups from local drive on $DATE_TIME."
        send_email "$subject" "$body"
    fi

    # Step 7: Remove old backups from Proton Drive
    if [ -f $PROTON_BACKUP ]; then

    # find -E $PROTON_DRIVE_DIR -type f -regex ".*/joplin_backup_.*\.zip" -mtime +7 -exec rm {} \;

        # For debugging the line above:
        find -E $PROTON_DRIVE_DIR -type f -regex ".*/joplin_backup_.*\.zip"  -mmin +3 -exec rm {} \;

        if [ $? -eq 0 ]; then
            echo "$DATE_TIME - Old backups on Proton Drive removed successfully." >> $LOG_FILE
        else
            echo "$DATE_TIME - Failed to remove old backups from Proton Drive." >> $LOG_FILE

            subject="Backup Cleanup Failure"
            body="Failed to remove old backups from Proton Drive on $DATE_TIME."
            send_email "$subject" "$body"                 
        fi
    else
        echo "$DATE_TIME - No backup found in proton drive." >> $LOG_FILE

        # Send email notification to self
        subject="Backup Failure"
        body="No backup found in proton drive on $DATE_TIME"
        send_email "$subject" "$body"
    fi

else
    echo "$DATE_TIME - Backup upload failed. Old backups will not be removed. " \
        "Unable to copy backup file to Proton Drive" >> $LOG_FILE
        
    # Send email notification on failure
    subject="Backup Failure - Proton Drive"
    body="Backup upload failed. Old backups were not removed at $DATE_TIME."
    send_email "$subject" "$body"
fi
