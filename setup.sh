#!/bin/bash

# Ensure the script is run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "Please run this script as root or use sudo."
  exit 1
fi

echo "Listing all connected storage devices:"
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE

# Array to store devices
declare -a devices
readarray -t devices < <(lsblk -dno NAME,TYPE | grep disk | awk '{print $1}')

# Display devices
index=1
for dev in "${devices[@]}"; do
    echo "$index) /dev/$dev"
    ((index++))
done

# User selects the device
read -rp "Enter the number corresponding to the device: " choice
selected_device="/dev/${devices[$choice-1]}"

# Show partitions on selected device
lsblk -o NAME,SIZE,MOUNTPOINT,FSTYPE "$selected_device"

# User selects the partition to mount (could add similar logic as above for partitions)
read -rp "Enter the partition name (e.g., ${selected_device}1): " selected_partition

# Mount point
read -rp "Enter your desired mount point (e.g., /mnt/ExternalDrive): " mount_dir
if [[ ! "$mount_dir" == /* ]]; then
    echo "Please enter an absolute path for the mount point."
    exit 1
fi
sudo mkdir -p "$mount_dir"

# Update /etc/fstab and attempt to mount
uuid=$(blkid -s UUID -o value "$selected_partition")
fstab_entry="UUID=$uuid $mount_dir $(lsblk -no FSTYPE "$selected_partition") defaults 0 2"
if ! grep -q "$uuid" /etc/fstab; then
    echo "$fstab_entry" | sudo tee -a /etc/fstab
    sudo mount "$selected_partition" "$mount_dir"
    # Check if the mount was successful
    if ! mountpoint -q "$mount_dir"; then
        echo "Mount failed, removing mount point and cleaning up fstab."
        sudo sed -i "\|${uuid}|d" /etc/fstab  # Remove the faulty fstab entry
        sudo rmdir "$mount_dir"
        exit 1
    fi
    sudo systemctl daemon-reload
else
    echo "UUID already in /etc/fstab, attempting to mount."
    sudo mount "$selected_partition" "$mount_dir"
    if ! mountpoint -q "$mount_dir"; then
        echo "Mount failed, mount point already exists in fstab but mount unsuccessful."
        exit 1
    fi
fi

echo "Mount successful at $mount_dir."
