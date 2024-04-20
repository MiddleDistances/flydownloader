#!/bin/bash

set -x

# Ensure mass storage device is connected
echo "Please ensure your mass storage device is plugged in."
read -rp "Press any key to continue..."
#!/bin/bash

# Ensure the script is run as root to avoid permission issues
if [[ $(id -u) -ne 0 ]]; then
  echo "Please run this script as root or use sudo."
  exit 1
fi

echo "Listing all connected storage devices:"
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE | grep disk

# Ask the user to specify the device
read -rp "Enter the device name (e.g., sda): " device_name

# Check if the device exists
if ! lsblk | grep -q "$device_name"; then
  echo "Device not found. Make sure you input the correct device name."
  exit 1
fi

# Find the partition on the selected device
partition_name=$(lsblk -o NAME,TYPE -p | grep "${device_name}" | grep -m 1 'part' | awk '{print $1}')

if [ -z "$partition_name" ]; then
  echo "No partition found on the selected device. Please check the device and try again."
  exit 1
fi

echo "Selected partition: $partition_name"

# Getting the filesystem type
fs_type=$(lsblk -no FSTYPE "$partition_name")
if [ -z "$fs_type" ]; then
  echo "Filesystem type not found for partition $partition_name."
  read -rp "Please specify the filesystem type manually (e.g., ext4, ntfs): " fs_type
fi

# Set the mount directory
read -rp "Enter your desired mount point (e.g., /mnt/ExternalDrive): " mount_dir

# Create the mount directory if it does not exist
if [ ! -d "$mount_dir" ]; then
  mkdir -p "$mount_dir"
  echo "Created mount directory at $mount_dir"
fi

# Update /etc/fstab
uuid=$(blkid -s UUID -o value "$partition_name")
fstab_entry="UUID=$uuid $mount_dir $fs_type defaults 0 2"

if ! grep -q "$uuid" /etc/fstab; then
  echo "$fstab_entry" >> /etc/fstab
  echo "Added $partition_name to /etc/fstab."
else
  echo "UUID already in /etc/fstab."
fi

# Mount the drive
mount "$partition_name" "$mount_dir"
echo "$partition_name has been mounted at $mount_dir."

# Verify the mount
if mountpoint -q "$mount_dir"; then
  echo "Mount verification successful."
else
  echo "Mount failed."
  exit 1
fi

# Adjust permissions
chown pi:pi "$mount_dir"
chmod 775 "$mount_dir"
echo "Permissions adjusted for $mount_dir"

echo "Setup complete! Your device $partition_name is set up at $mount_dir."


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
