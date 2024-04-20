#!/bin/bash

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

# Update /etc/fstab and mount
uuid=$(blkid -s UUID -o value "$selected_partition")
if ! grep -q "$uuid" /etc/fstab; then
    echo "UUID=$uuid $mount_dir ext4 defaults 0 2" | sudo tee -a /etc/fstab
    sudo mount -a
    sudo systemctl daemon-reload
else
    echo "UUID already in /etc/fstab."
fi

# Check mount
if mountpoint -q "$mount_dir"; then
    echo "Mount successful at $mount_dir."
else
    echo "Mount failed, please check the device and fstab."
fi


# Verify the mount
if mountpoint -q $mount_dir; then
  echo "Mount verification successful."
else
  echo "Mount failed. Check with 'dmesg' for more information."
  exit 1
fi

# Adjust permissions
chown pi:pi $mount_dir
chmod 775 $mount_dir
echo "Permissions adjusted for $mount_dir"

echo "Setup complete! Your device $partition_path is set up at $mount_dir."




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
