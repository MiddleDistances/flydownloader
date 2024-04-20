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

selected_part="/dev/$external_part"
echo "Selected partition: $selected_part"
echo "Mount point will be: $mount_dir"

# Get UUID and Filesystem Type
uuid=$(blkid -o value -s UUID "$selected_part")
fs_type=$(blkid -o value -s TYPE "$selected_part")

if [ -z "$uuid" ] || [ -z "$fs_type" ]; then
  echo "Failed to retrieve UUID or filesystem type for $selected_part."
  exit 1
fi

# Prepare /etc/fstab entry
fstab_entry="UUID=$uuid $mount_dir $fs_type defaults 0 2"

# Add to /etc/fstab if not already there
if ! grep -q "$uuid" /etc/fstab; then
  echo "$fstab_entry" >> /etc/fstab
  echo "Added to /etc/fstab: $fstab_entry"
else
  echo "UUID already in /etc/fstab."
fi

# Attempt to mount
if ! mount "$selected_part" "$mount_dir"; then
  echo "Mount failed, possibly due to NTFS being in an unsafe state."
  read -p "Would you like to reformat the partition to NTFS (suitable for large files but Windows only)? [y/N]: " ntfs_response
  if [[ "$ntfs_response" =~ ^[Yy]$ ]]; then
    umount "$selected_part" || umount -l "$selected_part"
    mkfs.ntfs -f -L NewVolume "$selected_part"
    mount "$selected_part" "$mount_dir"
    echo "Reformatted to NTFS and mounted at $mount_dir"
  else
    read -p "Would you like to reformat the partition to exFAT for broader compatibility (THIS WILL ERASE ALL DATA)? [y/N]: " exfat_response
    if [[ "$exfat_response" =~ ^[Yy]$ ]]; then
      umount "$selected_part" || umount -l "$selected_part"
      mkfs.exfat -n ExternalDrive "$selected_part"
      mount "$selected_part" "$mount_dir"
      echo "Reformatted to exFAT and mounted at $mount_dir"
    else
      echo "Operation aborted by the user."
      exit 1
    fi
  fi
else
  echo "$selected_part has been successfully mounted at $mount_dir."
fi

# Verify the mount
if mountpoint -q "$mount_dir"; then
  echo "Mount verification successful."
else
  echo "Mount failed after reformat, please check the details and try again."
  exit 1
fi

echo "Setup complete! Your device $selected_part is set up at $mount_dir."
