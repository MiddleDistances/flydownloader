#!/bin/bash

set -x

# Ensure mass storage device is connected
echo "Please ensure your mass storage device is plugged in."
read -rp "Press any key to continue..."

# List connected mass storage devices
echo "Listing all connected mass storage devices..."
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE | grep disk

# Get the device name from user input
read -rp "Enter the device name (e.g., sda1) to mount: " device_name

# Get the filesystem type automatically
fs_type=$(lsblk -no FSTYPE /dev/$device_name)

# Check if filesystem type is empty
if [ -z "$fs_type" ]; then
  echo "Filesystem type not found for device $device_name. Please specify the filesystem type manually."
  read -rp "Enter the filesystem type (e.g., ext4, ntfs): " fs_type
fi

# Mount the device
sudo mount /dev/$device_name $mount_dir

# Record the full device location as a variable
device_location="/dev/$device_name"

# Add an entry to /etc/fstab for automatic mounting on boot
echo "$device_location $mount_dir $fs_type defaults 0 0" | sudo tee -a /etc/fstab

echo "The device $device_name has been mounted at $mount_dir and will be automatically mounted on boot."

# Download the GitHub repository
echo "Downloading program files from GitHub..."
sudo apt-get install -y git
sudo git clone https://github.com/MiddleDistances/flydownloader.git /opt/flydownloader

# Change ownership of the flydownloader directory to the current user
echo "Changing ownership of the flydownloader directory..."
sudo chown -R $USER:$USER /opt/flydownloader

# Create a helper file with the mass storage directory
echo "$mount_dir" | sudo tee /opt/flydownloader/storage_path.txt

# Setup Python environment and install dependencies
echo "Setting up Python environment..."
sudo apt-get install -y python3-venv
python3 -m venv /opt/flydownloader/venv
source /opt/flydownloader/venv/bin/activate
pip install -r /opt/flydownloader/requirements.txt
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
valid users = $USER" | sudo tee -a /etc/samba/smb.conf

sudo systemctl restart smbd

# Create a systemd service to run the script at boot
echo "Creating systemd service..."
echo "\[Unit\]
Description=Fly Downloader Service
After=network.target

\[Service\]
ExecStart=/opt/flydownloader/venv/bin/python /opt/flydownloader/file_downloader.py
WorkingDirectory=/opt/flydownloader
EnvironmentFile=/opt/flydownloader/storage_path.txt
Restart=always

\[Install\]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/flydownloader.service

# Enable and start the service
sudo systemctl enable flydownloader.service
sudo systemctl start flydownloader.service

echo "Setup complete!"
