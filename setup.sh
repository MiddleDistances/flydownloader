#!/bin/bash

set -x

# Ensure mass storage device is connected
echo "Please ensure your mass storage device is plugged in."
read -rp "Press any key to continue..."

# List connected mass storage devices
echo "Listing all connected mass storage devices..."
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE | grep disk

# Get the device name from user input
read -rp "Enter the device name (e.g., sda): " device_name

# Find the partition on the selected device
partition_name=$(lsblk -o NAME,TYPE | grep "${device_name}" | grep part | awk '{print $1}')

if [ -z "$partition_name" ]; then
  echo "No partition found on the selected device. Please check the device and try again."
  exit 1
fi

# Get the filesystem type
fs_type=$(lsblk -no FSTYPE "/dev/$partition_name")

# Check if filesystem type is empty
if [ -z "$fs_type" ]; then
  echo "Filesystem type not found for partition $partition_name. Please specify the filesystem type manually."
  read -rp "Enter the filesystem type (e.g., ext4, ntfs): " fs_type
fi

# Set the mount directory
mount_dir="/mnt/$partition_name"

# Check if mount directory exists, if not create it
if [ ! -d "$mount_dir" ]; then
  sudo mkdir -p "$mount_dir"
fi

# Mount the partition
sudo mount "/dev/$partition_name" "$mount_dir"

# Check if the partition is already listed in /etc/fstab
if ! grep -q "$partition_name" /etc/fstab; then
  # Add the partition to /etc/fstab for automatic mounting on boot
  echo "/dev/$partition_name $mount_dir $fs_type defaults 0 0" | sudo tee -a /etc/fstab
fi

echo "The partition $partition_name has been mounted at $mount_dir and will be automatically mounted on boot."

# Get the current user
current_user=$(logname)


# Download the GitHub repository
echo "Downloading program files from GitHub..."
sudo apt-get install -y git
sudo rm -rf /home/$current_user/flydownloader  # Remove the existing directory and its contents
sudo git clone https://github.com/MiddleDistances/flydownloader.git /home/$current_user/flydownloader


# Change ownership of the flydownloader directory to the current user
echo "Changing ownership of the flydownloader directory..."
sudo chown -R $current_user:$current_user /home/$current_user/flydownloader

# Create a helper file with the mass storage directory
echo "$mount_dir" | sudo tee /home/$current_user/flydownloader/storage_path.txt

# Setup Python environment and install dependencies
echo "Setting up Python environment..."
sudo apt-get install -y python3-venv
python3 -m venv /home/$current_user/flydownloader/venv
source /home/$current_user/flydownloader/venv/bin/activate
pip install -r /home/$current_user/flydownloader/requirements.txt
deactivate

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
echo "Creating systemd service..."
echo "[Unit]
Description=Fly Downloader Service
After=network.target

[Service]
ExecStart=/home/$current_user/flydownloader/venv/bin/python /home/$current_user/flydownloader/USB_connect_download_v2.py
WorkingDirectory=/home/$current_user/flydownloader
Restart=always

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/flydownloader.service

# Enable and start the service
sudo systemctl enable flydownloader.service
sudo systemctl start flydownloader.service

echo "Setup complete!"
