#!/bin/bash

# Load the .env file
source /Users/garretmurray/JoplinBackup/.env

env > /Users/garretmurray/JoplinBackup/env_output.log

# Define backup variables
JOPLIN_EXPORT_DIR="$BACKUP_DIR/joplin_export"
DATE=$(date +"%Y-%m-%d")
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
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup successfully uploaded to Proton Drive." \
        >> $LOG_FILE

    # Step 6: Remove local old backups (older than 7 days)
    # find -E $BACKUP_DIR -type f -regex ".*/joplin_backup_.*\.(jex|zip)" -mtime +1 -exec rm {} \;

    # Debug find command (if modified more than a minute ago):
    find -E $BACKUP_DIR -type f -regex ".*/joplin_backup_.*\.(jex|zip)"  -mmin +1 -exec rm {} \;
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Old local backups removed successfully from " \
            "joplin_export folder and backup successfully uploaded to Proton Drive." \
            >> $LOG_FILE
        
        # Construct the email
        BODY="$(date '+%Y-%m-%d %H:%M:%S') - Old local backups removed successfully from 
        joplin_export folder on the local drive and backup successfully uploaded to Proton Drive."
        
        EMAIL="To: $ADDRESS\r\nSubject: Successful Backup of Joplin to Proton Drive\r\n
        From: $ADDRESS\r\n\r\n
        $BODY\r\n"
        echo $EMAIL

        # Send the email allowing special chars to be passed to msmtp
        echo -e $EMAIL | msmtp $ADDRESS
        printf "%d" $?


    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to remove old local backups. Error code 1" \
            >> $LOG_FILE

        # Send email notification to self
        BODY="$(date '+%Y-%m-%d %H:%M:%S') - Failed to remove old local backups. Error code 1"
        EMAIL="To: $ADDRESS\r\nSubject: $SUBJECT\r\nFrom: $ADDRESS\r\n\r\n$BODY\r\n"
        echo -e $EMAIL | msmtp $ADDRESS 
    fi

    # Step 7: Remove old backups from Proton Drive
    if [ -f $PROTON_BACKUP ]; then

    # find -E $PROTON_DRIVE_DIR -type f -regex ".*/joplin_backup_.*\.zip" -mtime +7 -exec rm {} \;

    # For debugging the line above:
    find -E $PROTON_DRIVE_DIR -type f -regex ".*/joplin_backup_.*\.zip"  -mmin +1 -exec rm {} \;

        if [ $? -eq 0 ]; then
            echo \
                "$(date '+%Y-%m-%d %H:%M:%S') - Old backups on Proton Drive removed successfully."\
                >> $LOG_FILE
        else
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Failed to "\
                "remove old backups on Proton Drive. Error code 2" \
                >> $LOG_FILE

            # Send email notification to self
            BODY="$(date '+%Y-%m-%d %H:%M:%S') - Failed to 
            remove old backups on Proton Drive. Error code 2"
            EMAIL="To: $ADDRESS\r\nSubject: $SUBJECT\r\nFrom: $ADDRESS\r\n\r\n$BODY\r\n"
            echo -e $EMAIL | msmtp $ADDRESS                  
        fi
    else
        echo "No backup found in proton drive. Error code 3" >> $LOG_FILE

        # Send email notification to self
        BODY="$(date '+%Y-%m-%d %H:%M:%S') - No backup found in proton drive. Error code 3"
        EMAIL="To: $ADDRESS\r\nSubject: $SUBJECT\r\nFrom: $ADDRESS\r\n\r\n$BODY\r\n"
        echo -e $EMAIL | msmtp $ADDRESS         
    fi

else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Backup upload failed. Old backups will not be removed."\
        "Error code 4" \
        >> $LOG_FILE
        
        # Send email notification to self
        BODY="$(date '+%Y-%m-%d %H:%M:%S') - No backup found in proton drive. "
        EMAIL="To: $ADDRESS\r\nSubject: $SUBJECT\r\nFrom: $ADDRESS\r\n\r\n$BODY\r\n"
        echo -e $EMAIL | msmtp $ADDRESS
fi
