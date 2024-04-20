#!/bin/bash

# Ensure the script is run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

echo "Listing all connected storage devices:"
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE

# Automatically identify the first external partition
external_part=$(lsblk -rno NAME,TYPE,MOUNTPOINT | awk '$2=="part" && $3=="" {print $1; exit}')

if [ -z "$external_part" ]; then
  echo "No suitable external partitions found. Please ensure your external drive is connected."
  exit 1
fi

# Create a mount point in /mnt if not already existing
mount_dir="/mnt/auto_mounted_drive"
mkdir -p "$mount_dir"

echo "Selected partition: /dev/$external_part"
echo "Mount point will be: $mount_dir"

# Get UUID and Filesystem Type
uuid=$(blkid -o value -s UUID "/dev/$external_part")
fs_type=$(blkid -o value -s TYPE "/dev/$external_part")

if [ -z "$uuid" ] || [ -z "$fs_type" ]; then
  echo "Failed to retrieve UUID or filesystem type for /dev/$external_part."
  exit 1
fi

# Prepare /etc/fstab entry
fstab_entry="UUID=$uuid $mount_dir $fs_type defaults 0 2"

# Check if UUID already in /etc/fstab and add if not
if ! grep -q "$uuid" /etc/fstab; then
  echo "$fstab_entry" >> /etc/fstab
  echo "Added to /etc/fstab: $fstab_entry"
else
  echo "UUID already in /etc/fstab."
fi

# Mount the drive
mount "/dev/$external_part" "$mount_dir" && echo "/dev/$external_part has been successfully mounted at $mount_dir."

# Verify the mount
if mountpoint -q "$mount_dir"; then
  echo "Mount verification successful."
else
  echo "Mount failed, please check the details and try again."
  exit 1
fi

echo "Setup complete! Your device /dev/$external_part is set up at $mount_dir."
