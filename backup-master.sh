#!/bin/bash

set -e

# CONFIGURATION - EDIT BEFORE USE

# Your Linux username (replace with your actual username)
REAL_USER="your_username_here"
USER_HOME="/home/$REAL_USER"

# Paths to back up - adjust as needed
INCLUDE_PATHS="/home /etc /usr/local"

# Backup directories with fallbacks
BACKUP_DIR="$USER_HOME/Documents/backup-files" # Edit this path with your custom filename
BACKUP_DIR_FALLBACK1="$USER_HOME/Documents"
BACKUP_DIR_FALLBACK2="$USER_HOME/Desktop"

# END CONFIGURATION

# Exclude unnecessary or sensitive directories
EXCLUDES=(
  --exclude="/home/*/.cache"
  --exclude="/home/*/.mozilla"
  --exclude="/home/*/.config/google-chrome"
  --exclude="/home/*/.local/share/Trash"
  --exclude="/var/log"
  --exclude="/var/cache"
  --exclude="/proc"
  --exclude="/sys"
  --exclude="/dev"
  --exclude="/run"
  --exclude="/tmp"
  --exclude="/mnt"
  --exclude="/media"
  --exclude="/lost+found"
  --exclude="$BACKUP_DIR"
)

# Use first valid backup directory
if [ ! -d "$BACKUP_DIR" ]; then
  if [ -d "$BACKUP_DIR_FALLBACK1" ]; then
    BACKUP_DIR="$BACKUP_DIR_FALLBACK1"
  elif [ -d "$BACKUP_DIR_FALLBACK2" ]; then
    BACKUP_DIR="$BACKUP_DIR_FALLBACK2"
  else
    echo "❌ No suitable backup directory found. Exiting."
    exit 1
  fi
fi

mkdir -p "$BACKUP_DIR"

# Filenames with timestamp
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
BACKUP_FILENAME="backup_${TIMESTAMP}.tar.gz"
ENCRYPTED_FILENAME="${BACKUP_FILENAME}.gpg"

BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILENAME}"
ENCRYPTED_PATH="${BACKUP_DIR}/${ENCRYPTED_FILENAME}"

# Ensure GPG uses your user’s keyring (not root’s)
export GNUPGHOME="$USER_HOME/.gnupg"

# Create and encrypt backup
create_backup() {
  echo "📦 Creating compressed backup archive..."
  tar -czf "$BACKUP_PATH" "${EXCLUDES[@]}" $INCLUDE_PATHS

  echo "🔐 Encrypting archive with GPG..."
  gpg --batch --yes --symmetric --cipher-algo AES256 --output "$ENCRYPTED_PATH" "$BACKUP_PATH"

  echo "🧹 Cleaning up unencrypted archive..."
  rm -f "$BACKUP_PATH"
}

# Create the backup
create_backup

# Retry once if encryption file missing
if [ ! -f "$ENCRYPTED_PATH" ]; then
  echo "⚠️ Encrypted file missing after first attempt. Retrying..."
  create_backup

  if [ ! -f "$ENCRYPTED_PATH" ]; then
    echo "❌ Encryption failed after second attempt. Exiting."
    exit 1
  fi
fi

echo "✅ Encrypted backup created: $ENCRYPTED_PATH"

# Upload to Google Drive with rclone
if command -v rclone >/dev/null 2>&1; then
  echo "☁️ Checking rclone remote 'gdrive'..."
  if rclone ls gdrive: >/dev/null 2>&1; then
    echo "📁 Ensuring 'System-Backups' folder exists..."
    if ! rclone lsd gdrive: | grep -q "System-Backups"; then
      echo "📁 'System-Backups' not found. Creating..."
      rclone mkdir gdrive:System-Backups
    fi

    echo "⬆️ Uploading encrypted backup to Google Drive..."
    if rclone copy "$ENCRYPTED_PATH" gdrive:System-Backups --progress; then 	# Make sure to edit the remote path to the one you created, if different from default
      echo "✅ Upload successful!"
    else
      echo "⚠️ Upload failed. Backup remains at: $ENCRYPTED_PATH"
    fi
  else
    echo "⚠️ Could not access rclone remote 'gdrive'. Skipping upload."
  fi
else
  echo "⚠️ rclone not installed. Skipping upload."
fi

echo "🎉 Backup process completed successfully."

