import os
import subprocess
import pyudev
from datetime import datetime, timedelta
from tqdm import tqdm
import shutil
import time
import heapq

def read_configuration():
    logged_in_user = os.getlogin()
    print(f"The logged-in user is: {logged_in_user}")
    # Set default values for configuration
    config = {'username': 'pi', 'mount_dir': '/mnt/auto_mounted_drive'}  # default user

    try:
        with open(f"/home/{logged_in_user}/flydownloader/storage_path.txt", "r") as file:
            lines = file.readlines()
            for line in lines:
                key, value = line.strip().split('=')
                config[key] = value
    except FileNotFoundError:
        print("Configuration file not found. Using default settings.")
    except ValueError:
        print("Error reading configuration. Ensure it is in key=value format.")

    return config

def check_disk_usage(path):
    """ Check disk space and return total, used, and free space in bytes. """
    total, used, free = shutil.disk_usage(path)
    return total, used, free

def delete_oldest_file(directory, file_prefix="CYQ"):
    """ Delete the oldest file in the directory and its subdirectories starting with a specific prefix. """
    oldest_file = None
    oldest_time = None

    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.startswith(file_prefix):
                file_path = os.path.join(root, file)
                file_time = os.path.getctime(file_path)
                if oldest_file is None or file_time < oldest_time:
                    oldest_file = file_path
                    oldest_time = file_time

    if oldest_file:
        os.remove(oldest_file)
        print(f"Deleted the oldest file: {oldest_file}")
    else:
        print("No files with the specified prefix to delete.")

def is_camera_connected(device_name):
    context = pyudev.Context()
    for device in context.list_devices(subsystem='block', DEVTYPE='partition'):
        if device.get('ID_FS_LABEL') == device_name:
            return device.device_node
    return None

import os
import subprocess
from datetime import datetime

def generate_mount_point(base_path):
    """Generates a unique mount point by appending a timestamp."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    return f"{base_path}_{timestamp}"

def mount_device(device_path, mount_point):
    if os.path.ismount(mount_point):
        # Check if the correct device is mounted there
        # current_device = os.path.realpath('/dev/disk/by-uuid/' + os.readlink('/dev/disk/by-uuid').split('/')[-1])
        # if current_device == device_path:
        #     print(f"Device {device_path} is already mounted at {mount_point}.")
        #     return
        with open('/proc/mounts', 'r') as f:
            mounts = f.read()
        if device_path in mounts:
            print(f"Device {device_path} is already mounted at {mount_point}.")
            return
        else:
            print(f"Another device is mounted at {mount_point}. Generating a new mount point.")
            mount_point = generate_mount_point(mount_point)
            os.makedirs(mount_point, exist_ok=True)

    try:
        subprocess.run(['sudo', 'mount', device_path, mount_point], check=True)
        print(f"Device mounted at {mount_point}.")
    except subprocess.CalledProcessError as e:
        print(f"Failed to mount {device_path} at {mount_point}: {e}")
        raise



def unmount_device(mount_point):
    subprocess.run(['sudo', 'umount', mount_point], check=True)


def download_new_files(source_dir, destination_dir):
    required_free_space = 0.5  # 20% of disk space should be kept free
    downloaded_files = []
    total_transfer_size = 0  # Initialize the total size of files to be transferred
    disk_total, disk_used, disk_free = check_disk_usage(destination_dir)
    print(f"Total space: {disk_total / 2**30:.2f} GB, Used space: {disk_used / 2**30:.2f} GB, Free space: {disk_free / 2**30:.2f} GB")

    for root, dirs, files in os.walk(source_dir):
        for file in files:
            if file.lower().endswith(('.mp4', '.mov')):  # Ensure it handles only video files
                source_file = os.path.join(root, file)
                file_stat = os.stat(source_file)
                creation_time = datetime.fromtimestamp(file_stat.st_ctime)  # Get creation time for folder naming
                date_folder = creation_time.strftime('%Y%m%d')  # Format the date
                date_dir_path = os.path.join(destination_dir, date_folder)

                if not os.path.exists(date_dir_path):
                    os.makedirs(date_dir_path, exist_ok=True)

                destination_file = os.path.join(date_dir_path, file)
                file_size = os.path.getsize(source_file)

                if not os.path.exists(destination_file):
                    while disk_free - file_size <= disk_total * required_free_space:
                        print(f"Insufficient space to copy {file}. Deleting the oldest file to free space.")
                        delete_oldest_file(destination_dir)
                        _, _, disk_free = check_disk_usage(destination_dir)
                        if disk_free - file_size > disk_total * required_free_space:
                            break  # Exit loop if enough space has been freed
                        
                    print(f"Copying {file} to {destination_file}")
                    with open(source_file, 'rb') as fsrc, open(destination_file, 'wb') as fdst, \
                        tqdm(total=file_size, unit='B', unit_scale=True, desc=file) as pbar:
                        for chunk in iter(lambda: fsrc.read(4096), b''):
                            fdst.write(chunk)
                            pbar.update(len(chunk))

                    downloaded_files.append(destination_file)
                    total_transfer_size += file_size  # Add to total transfer size

    return downloaded_files, total_transfer_size  # Return both the list of downloaded files and the total size

def get_video_metadata(video_path):
    """Extract metadata from video file using ffprobe."""
    cmd = [
        'ffprobe', '-v', 'error', '-select_streams', 'v:0',
        '-show_entries', 'stream_tags=creation_time:format=duration',
        '-of', 'default=noprint_wrappers=1:nokey=1', video_path
    ]
    output = subprocess.run(cmd, stdout=subprocess.PIPE, text=True).stdout.split()
    try:
        creation_time = datetime.strptime(output[0], '%Y-%m-%dT%H:%M:%S.%fZ')
        duration = float(output[1])
        return {'creation_time': creation_time, 'duration': duration}
    except Exception as e:
        print(f"Error processing metadata for {video_path}: {e}")
        return {'creation_time': None, 'duration': 0}

def create_movie_from_clips(video_paths, output_dir):
    if not video_paths:
        print("No video files to concatenate.")
        return

    # Retrieve metadata for each video and sort by creation time
    videos = []
    for video in video_paths:
        metadata = get_video_metadata(video)
        if metadata['creation_time'] is None:
            continue
        end_time = metadata['creation_time'] + timedelta(seconds=metadata['duration'])
        videos.append({'path': video, 'start_time': metadata['creation_time'], 'end_time': end_time})

    videos.sort(key=lambda x: x['start_time'])

    # Group videos based on continuity
    groups = []
    current_group = []
    last_end_time = None

    for video in videos:
        start_time = video['start_time']
        if last_end_time is None or start_time - last_end_time <= timedelta(seconds=60):  # 60 seconds buffer
            current_group.append(video['path'])
        else:
            groups.append(current_group)
            current_group = [video['path']]
        last_end_time = video['end_time']

    if current_group:
        groups.append(current_group)

    # Create movies for each group
    for group in groups:
        if group:
            first_video = group[0]
            first_video_date = get_video_metadata(first_video)['creation_time']
            output_file = os.path.join(output_dir, f"movie_{first_video_date.strftime('%Y%m%d_%H%M%S')}.mp4")
            concat_file_path = os.path.join('/tmp', f"concat_{first_video_date.strftime('%Y%m%d_%H%M%S')}.txt")
            with open(concat_file_path, 'w') as concat_file:
                concat_file.writelines(f"file '{video}'\n" for video in group)

            ffmpeg_cmd = ['ffmpeg', '-f', 'concat', '-safe', '0', '-i', concat_file_path, '-c', 'copy', '-y', output_file]
            try:
                subprocess.run(ffmpeg_cmd, check=True)
                print(f"Successfully created movie: {output_file}")
            except subprocess.CalledProcessError as e:
                print(f"Failed to create movie from clips. Error: {e}")


def main():
    config = read_configuration()
    device_name = 'FLY6PRO'
    mount_point = f"/media/{config['username']}/{device_name}" 
    destination_dir = config['mount_dir']  # destination_dir is the same as the mount point

    print('Monitoring for camera connection...')
    while True:
        device_path = is_camera_connected(device_name)  # Assuming device_name is constant
        if device_path:
            print('Camera connected. Mounting device...')
            try:
                mount_device(device_path, mount_point)
                print('Device mounted. Starting file download...')

                all_downloaded_files = []
                for source_dir_suffix in ['DCIM/100_RIDE', 'DCIM/101_RIDE', 'DCIM/102_RIDE']:
                    source_dir = os.path.join(mount_point, source_dir_suffix)
                    if os.path.exists(source_dir):
                        downloaded_files, total_size = download_new_files(source_dir, destination_dir)
                        all_downloaded_files.extend(downloaded_files)
                    else:
                        print(f"Source directory {source_dir} does not exist.")
                print('File download complete. Creating movie from downloaded clips...')
                create_movie_from_clips(all_downloaded_files, destination_dir)
                print('Movie creation complete. Unmounting device...')
                unmount_device(mount_point)
                print('Device unmounted. Waiting for camera to be reconnected...')
            except subprocess.CalledProcessError as e:
                print(f"Error occurred while mounting or unmounting the device: {str(e)}")
            
            while is_camera_connected('FLY6PRO'):
                time.sleep(1)  # Wait until the camera is disconnected

        else:
            print('Camera not connected. Waiting...')
            time.sleep(5)  # Check for camera connection every 5 seconds


if __name__ == "__main__":
    main()
