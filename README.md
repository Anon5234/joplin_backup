# Joplin Backup Script

This project contains a Bash script that automates the process of backing up Joplin notes, securely uploading them to AWS S3, and managing old (locally stored) backups. The script retrieves sensitive credentials from HashiCorp Vault and assumes an AWS IAM role to access S3.

## Features

- Automates the backup of Joplin notes.
- Compresses the backup file and uploads it to an S3 bucket.
- Uses HashiCorp Vault for secure secret management.
- Cleans up old local backups (older than 7 days).
- Logs actions taken and sends email notifications upon failure using msmtp.

## Prerequisites

- [HashiCorp Vault](https://www.vaultproject.io/)
- [AWS CLI](https://aws.amazon.com/cli/) with S3 access configured
- [msmtp](https://marlam.de/msmtp/) for sending email notifications
- A `.env` file containing necessary environment variables

## .env File

The `.env` file must contain the following environment variables:

```bash
# Directory to store the backup files
BACKUP_DIR="/path/to/joplin/backup"

# AWS S3 bucket name
BUCKET_NAME="your-s3-bucket-name"

# Vault variables for accessing credentials
VAULT_ADDR="https://your-vault-server"
VAULT_APPROLE_ROLE_ID="your-approle-role-id"
VAULT_APPROLE_SECRET_ID="your-approle-secret-id"
VAULT_CACERT="/path/to/vault/ca-cert"
VAULT_CLIENT_CERT="/path/to/vault/client-cert"
VAULT_CLIENT_KEY="/path/to/vault/client-key"

# Email settings for msmtp
ADDRESS="your-email@example.com"
MAIL_BRIDGE="/path/to/mail-bridge-in-vault"
MAIL_BRIDGE_PASS_RAW=".data.password"

# S3 IAM Role information
ROLE_ARN="arn:aws:iam::ACCOUNT_NUM:role/YourRole"
SESSION_NAME="BackupSession"

# Logging
LOG_FILE="/path/to/joplin/log"
```

**Note**: Ensure that your `.env` file is not included in your public repository by adding it to `.gitignore`.

## Usage

1. Set up the environment:

	- Ensure that msmtp, AWS CLI, and Vault are installed and configured on your system.
	- Create a `.env` file with the necessary environment variables (as outlined above).

2. Configure HashiCorp Vault:

	-  Set up Vault with the necessary secrets for AWS access and email credentials. Ensure the AppRole for Vault is configured and the secrets path is correct.

3. Run the script: Execute the backup script manually or via a cron job:

```
/path/to/joplin_backup.sh /path/to/.env
```

Alternatively, schedule it with cron. For example, to run the backup at 10:00 PM every day:

```
0 22 * * * /path/to/joplin_backup.sh /path/to/.env >> /path/to/joplin_backup.log  2>&1
```

4. Email Notifications:

	- The script sends an email notification upon failure of S3 upload failure. Emails are sent using msmtp, with credentials dynamically retrieved from Vault.

## Script Breakdown

### Steps Performed by the Script:

1. Unset AWS Credentials:

	- Unsets any pre-existing AWS credentials to avoid conflicts.

2. Load Environment Variables:

	- Loads sensitive environment variables from the `.env` file passed as an argument.

3. Authenticate with Vault:

	- Authenticates using the AppRole method to retrieve a Vault token and then retrieves AWS and email credentials securely from Vault.

4. Assume AWS IAM Role:

	- Uses AWS STS to assume an IAM role and get temporary credentials for S3 access.

5. Backup Joplin Notebooks:

	- Copies the Joplin notes export file, compresses it into a .zip, and uploads it to S3. Vesioning and lifecycle management are handled by the S3 bucket.

6. Error Handling and Email Notifications:

	- Sends an email if there's a failure in uploading the backup to S3.

7. Old Backup Cleanup:

	- Deletes local backup files older than 7 days to conserve disk space.

## Example Cron Job

To automate the backup process, you can add the following cron job to your crontab:

```
30 18,19,20,21,22,23 * * * /path/to/joplin_backup.sh /path/to/.env >> /path/to/joplin_backup.log 2>&1
```
This will run the backup script at 18:30, 19:30, 20:30, 21:30, 22:30, and 23:30 each day.

## Logging

	- All logs are written to the log file specified in the `.env` file (LOG_FILE).
	- The log records details about the backup, including the time of backup, any errors encountered, and whether old backups were successfully deleted.

## Error Handling

	- If tthe backup upload to S3 fails, an email notification will be sent with the relevant log details.

##  Contributing
Feel free to open issues or submit pull requests to improve this script!

## License
This project is licensed under the MIT License.


