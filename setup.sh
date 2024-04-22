#!/bin/bash

# Ensure the script is run as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root or with sudo."
  exit 1
fi

#lets do an update
echo "Always best to start with an update. We are going to check for updates now."
sudo apt-get update
sudo apt-get upgrade


echo "Listing all connected storage devices:"
lsblk -o NAME,MODEL,SIZE,MOUNTPOINT,FSTYPE,TYPE

# Store all partitions in an array
mapfile -t partitions < <(lsblk -rno NAME,TYPE,MOUNTPOINT | awk '$2=="part" {print $1}')

if [ ${#partitions[@]} -eq 0 ]; then
  echo "No partitions found. Please ensure your external drive is connected."
  exit 1
fi

echo "Available partitions:"
for i in "${!partitions[@]}"; do
  echo "$((i+1))) /dev/${partitions[i]}"
done

# Prompt the user to choose a partition by number
read -p "Enter the number of the partition where you want to place your files: " num
selected_index=$((num-1))

# Validate user input
if [[ $selected_index -lt 0 || $selected_index -ge ${#partitions[@]} ]]; then
  echo "Invalid selection. Exiting."
  exit 1
fi

selected_partition="/dev/${partitions[selected_index]}"
echo "You have selected $selected_partition."

# Continue with the setup logic here
mount_dir="/mnt/auto_mounted_drive"
mkdir -p "$mount_dir"

# Mount the partition
if mountpoint -q "$mount_dir"; then
  echo "$selected_partition is already mounted."
else
  mount $selected_partition $mount_dir && echo "$selected_partition has been successfully mounted at $mount_dir."
  if [ $? -ne 0 ]; then
    echo "Failed to mount $selected_partition. Check if it's formatted correctly and not in use."
    exit 1
  fi
fi

# Verify the mount
if mountpoint -q "$mount_dir"; then
  echo "Mount verification successful. Setup complete! Your files can be placed in $mount_dir."
else
  echo "Mount failed, please check the details and try again."
  exit 1
fi

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
echo "Changing ownership of the storage directory..."
sudo chown -R $current_user:$current_user $mount_dir

# Create a helper file with the mass storage directory and username
echo "mount_dir=$mount_dir" | sudo -u "$current_user" tee "/home/$current_user/flydownloader/storage_path.txt"
echo "username=$current_user" | sudo -u "$current_user" tee -a "/home/$current_user/flydownloader/storage_path.txt"


# Setup Python environment and install dependencies
echo "Setting up Python environment..."
sudo apt-get install -y python3-venv
python3 -m venv /home/$current_user/flydownloader/venv
source /home/$current_user/flydownloader/venv/bin/activate
pip install -r /home/$current_user/flydownloader/requirements.txt
deactivate


# Update system and install Samba
echo "Installing Samba..."
sudo apt-get update
sudo apt-get install samba samba-common-bin -y

# Backup existing Samba configuration
echo "Backing up existing Samba configuration..."
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# Configure Samba
echo "Configuring Samba..."
sudo bash -c "cat > /etc/samba/smb.conf <<EOT
[global]
workgroup = WORKGROUP
server string = Samba Server
security = user
map to guest = bad user
create mask = 0664
directory mask = 0775

[CycPiNas]
path = $mount_dir
writeable = Yes
create mask = 0664
directory mask = 0775
public = no
browsable = yes
valid users = $current_user
EOT"

# Restart Samba services
echo "Restarting Samba services..."
sudo systemctl restart smbd
sudo systemctl restart nmbd

# Adding user to Samba
echo "Adding user to Samba..."
sudo smbpasswd -a $current_user

# Set permissions and ownership for the mount directory
echo "Setting permissions for the mount directory..."
sudo chown $current_user:$current_user $mount_dir
sudo chmod 0775 $mount_dir

echo "Samba has been configured. Your share is available on the network."



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
