#!/bin/bash

echo "Listing all connected storage devices:"
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE | grep -E 'disk|part'

# Prompt user to select a device or partition
read -rp "Enter the device name (e.g., sda): " device_name

# Validate device name
if ! lsblk | grep -q "$device_name"; then
  echo "Device not found. Make sure you input the correct device name."
  exit 1
fi

echo "Selected device: /dev/$device_name"

# Get partition details
lsblk -o NAME,SIZE,MOUNTPOINT,FSTYPE "/dev/$device_name" | grep 'part'
read -rp "Enter the partition name (e.g., ${device_name}1): " selected_partition

# Full path for partition
partition_path="/dev/$selected_partition"

# Mount point
read -rp "Enter your desired mount point (e.g., /mnt/ExternalDrive): " mount_dir
sudo mkdir -p "$mount_dir"

# Get UUID
uuid=$(blkid -s UUID -o value "$partition_path")
if [[ -z "$uuid" ]]; then
  echo "Failed to get UUID for $partition_path. Ensure the partition exists."
  exit 1
fi

# Add to fstab
fstab_entry="UUID=$uuid $mount_dir $(lsblk -no FSTYPE "$partition_path") defaults 0 2"
if ! grep -q "$uuid" /etc/fstab; then
  echo "$fstab_entry" | sudo tee -a /etc/fstab
fi

# Attempt to mount
sudo mount "$partition_path" "$mount_dir"
if mountpoint -q "$mount_dir"; then
  echo "$partition_path has been mounted at $mount_dir."
else
  echo "Mount failed, cleaning up fstab and mount point."
  sudo sed -i "\|${uuid}|d" /etc/fstab  # Remove the faulty fstab entry
  sudo rmdir "$mount_dir"
  exit 1
fi

echo "Setup complete!"

