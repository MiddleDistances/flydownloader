#!/bin/bash

echo "Listing all connected storage devices:"
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE

# This command will now include all partitions, not just unmounted ones
all_partitions=$(lsblk -rno NAME,TYPE,MOUNTPOINT | awk '$2=="part" {print $1}')

if [ -z "$all_partitions" ]; then
  echo "No partitions found. Please ensure your external drive is connected."
  exit 1
fi

echo "Available partitions:"
echo "$all_partitions"

# Example to select a partition manually for operations
echo "Please type the name of the partition you want to setup (e.g., sda1):"
read selected_partition

# Check if the user input matches an actual device
if [[ " $all_partitions " =~ " $selected_partition " ]]; then
  echo "Setting up /dev/$selected_partition"
  # Your setup logic here
else
  echo "Partition $selected_partition not found among available devices."
  exit 1
fi

# Dummy setup logic for the chosen partition
echo "Selected partition: /dev/$selected_partition will be set up."
# Insert real operations such as mount, format, etc., here.

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


# Get the current user
current_user=$(logname)
# Download the GitHub repository
echo "Downloading program files from GitHub..."
sudo apt-get install -y git
sudo rm -rf /home/$current_user/flydownloader  # Remove the existing directory and its contents
sudo git clone https://github.com/MiddleDistances/flydownloader.git /home/$current_user/flydownloader
# Create a helper file with the mass storage directory and username
echo "mount_dir=$mount_dir" | sudo -u "$current_user" tee "/home/$current_user/flydownloader/storage_path.txt"
echo "username=$current_user" | sudo -u "$current_user" tee -a "/home/$current_user/flydownloader/storage_path.txt"
# Change ownership of the flydownloader directory to the current user
echo "Changing ownership of the flydownloader directory..."
sudo chown -R $current_user:$current_user /home/$current_user/flydownloader
# Setup Python environment and install dependencies
echo "Setting up Python environment..."
sudo apt-get install -y python3-venv
python3 -m venv /home/$current_user/flydownloader/venv
source /home/$current_user/flydownloader/venv/bin/activate
pip install -r /home/$current_user/flydownloader/requirements.txt
deactivate
#install samba
sudo apt-get install samba -y
sudo systemctl restart smbd
# Configure Samba to share the mounted device
echo "Configuring Samba..."
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
echo "\[global\]
workgroup = WORKGROUP
server string = Samba Server
security = user
create mask = 0664
directory mask = 0775
\[$device_name\]
path = $mount_dir
writeable = Yes
create mask = 0664
directory mask = 0775
public = no
valid users = $current_user" | sudo tee -a /etc/samba/smb.conf
sudo systemctl restart smbd
# Create a systemd service to run the script at boot
echo 'Creating systemd service...1'
sudo tee /etc/systemd/system/flydownloader.service <<EOF
[Unit]
Description=Fly Downloader Service
After=network.target
[Service]
ExecStart=/home/pi/flydownloader/venv/bin/python /home/pi/flydownloader/USB_connect_download_v2.py
WorkingDirectory=/home/pi/flydownloader
Restart=always
[Install]
WantedBy=multi-user.target
EOF
# Enable and start the service
sudo systemctl enable flydownloader.service
sudo systemctl start flydownloader.service
echo "Setup complete!"
