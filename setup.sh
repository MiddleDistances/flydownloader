#!/bin/bash

# Ask user to plug in mass storage and wait for confirmation
echo "Please ensure your mass storage device is plugged in."
read -p "Press Enter to continue..."

# List all connected mass storage devices and ask user to choose one
echo "Listing all connected mass storage devices..."
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE | grep disk

read -p "Enter the device name (e.g., sda1) to mount: " device_name

# Mount the device if not already mounted
if [ ! -d "/media/$device_name" ]; then
  sudo mkdir -p /media/$device_name
fi
sudo mount /dev/$device_name /media/$device_name

# Download the GitHub repository
echo "Downloading program files from GitHub..."
sudo apt-get install -y git
git clone https://github.com/MiddleDistances/flydownloader.git /opt/flydownloader

# Create a helper file with the mass storage directory
echo "/media/$device_name" > /opt/flydownloader/storage_path.txt

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

echo "[global]
workgroup = WORKGROUP
server string = Samba Server
security = user
create mask = 0664
directory mask = 0775
force user = root
force group = root

[$device_name]
path = /media/$device_name
writeable = Yes
create mask = 0777
directory mask = 0777
public = no" | sudo tee -a /etc/samba/smb.conf

sudo systemctl restart smbd

# Create a systemd service to run the script at boot
echo "Creating systemd service..."

echo "[Unit]
Description=Fly Downloader Service
After=network.target

[Service]
ExecStart=/opt/flydownloader/venv/bin/python /opt/flydownloader/file_downloader.py
WorkingDirectory=/opt/flydownloader
EnvironmentFile=/opt/flydownloader/storage_path.txt
Restart=always

[Install]
WantedBy=multi-user.target" | sudo tee /etc/systemd/system/flydownloader.service

# Enable and start the service
sudo systemctl enable flydownloader.service
sudo systemctl start flydownloader.service

echo "Setup complete!"