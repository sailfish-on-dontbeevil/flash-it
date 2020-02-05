#!/bin/bash

VERSION="0.2.0"
BRANCH=master
UBOOT_JOB=u-boot
UBOOT_DIR=u-boot-bootloader
ROOTFS_PINEPHONE_JOB=pinephone-rootfs
ROOTFS_PINETAB_JOB=pinetab-rootfs
ROOTFS_DEVKIT_JOB=devkit-rootfs
ROOTFS_PINEPHONE_DIR=pinephone
ROOTFS_PINETAB_DIR=pinetab
ROOTFS_DEVKIT_DIR=devkit
MOUNT_DATA=./data
MOUNT_BOOT=./boot

# Parse arguments
# https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -b|--branch)
        BRANCH="$2"
        shift
        shift
        ;;
    -h|--help)
        echo "Sailfish OS flashing script for Pine64 devices"
        echo ""
        printf '%s\n' \
               "This script will download the latest Sailfish OS image for the Pine" \
               "Phone, Pine Phone dev kit, or Pine Tab. It requires that you have a" \
               "micro SD card inserted into the computer." \
               "" \
               "usage: flash-it.sh [-b BRANCH]" \
               "" \
               "Options:" \
               "" \
               "	-b, --branch BRANCH	Download images from a specific Git branch." \
               "	-h, --help		Print this help and exit." \
               "" \
               "This command requires: parted, sudo, wget, tar, unzip, lsblk," \
               "mkfs.ext4." \
               ""\
               "Some distros do not have parted on the PATH. If necessary, add" \
               "parted to the PATH before running the script."

        exit 0
        shift
        ;;
    *) # unknown argument
        POSITIONAL+=("$1") # save it in an array for later
        shift # past argument
        ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# Helper functions
# Error out if the given command is not found on the PATH.
function check_dependency {
    dependency=$1
    command -v $dependency >/dev/null 2>&1 || {
        echo >&2 "${dependency} not found. Please make sure it is installed and on your PATH."; exit 1;
    }
}

# Determine if wget supports the --show-progress option (introduced in
# 1.16). If so, make use of that instead of spewing out redirects and
# loads of info into the terminal.
function wget_cmd {
    wget --show-progress > /dev/null 2>&1
    status=$?

    # Exit code 2 means command parsing error (i.e. option does not
    # exist).
    if [ "$status" == "2" ]; then
        echo "wget -O"
    else
        echo "wget -q --show-progress -O"
    fi
}

# Check dependencies
check_dependency "parted"
check_dependency "sudo"
check_dependency "wget"
check_dependency "tar"
check_dependency "unzip"
check_dependency "lsblk"
check_dependency "mkfs.ext4"

# Different branch for some reason?
if [ "${BRANCH}" != "master" ]; then
    echo -e "\e[1m\e[97m!!! Will flash image from ${BRANCH} branch !!!\e[0m"
fi

# Header
echo -e "\e[1m\e[91mSailfish OS Pine64 device flasher V$VERSION\e[0m"
echo "======================================"
echo ""

# Image selection
echo -e "\e[1mWhich image do you want to flash?\e[0m"
select OPTION in "PinePhone device" "PineTab device" "Dont Be Evil devkit"; do
    case $OPTION in
        "PinePhone device" ) ROOTFS_JOB=$ROOTFS_PINEPHONE_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONE_DIR; break;;
        "PineTab device" ) ROOTFS_JOB=$ROOTFS_PINETAB_JOB; ROOTFS_DIR=$ROOTFS_PINETAB_DIR; break;;
        "Dont Be Evil devkit" ) ROOTFS_JOB=$ROOTFS_DEVKIT_JOB; ROOTFS_DIR=$ROOTFS_DEVKIT_DIR; break;;
    esac
done

# Check if already downloaded before downloading
ls u-boot.zip || {
	# Downloading images
	echo -e "\e[1mDownloading images...\e[0m"
	WGET=$(wget_cmd)
	UBOOT_DOWNLOAD="https://gitlab.com/sailfishos-porters-ci/dont_be_evil-ci/-/jobs/artifacts/$BRANCH/download?job=$UBOOT_JOB"
	$WGET "${UBOOT_JOB}.zip" "${UBOOT_DOWNLOAD}" || {
    	echo >&2 "UBoot image download failed. Aborting."
    	exit 2
	}
}

# Check if already downloaded before downloading
ls pinephone-rootfs.zip || {
	ROOTFS_DOWNLOAD="https://gitlab.com/sailfishos-porters-ci/dont_be_evil-ci/-/jobs/artifacts/$BRANCH/download?job=$ROOTFS_JOB"
	$WGET "${ROOTFS_JOB}.zip" "${ROOTFS_DOWNLOAD}" || {
    	echo >&2 "Root filesystem image download failed. Aborting."
    	exit 2
	}
}

# Select flash target
echo -e "\e[1mWhich SD card do you want to flash?\e[0m"
lsblk
read -p "Device node (/dev/sdX): " DEVICE_NODE
echo "Flashing image to: $DEVICE_NODE"
echo "WARNING: All data will be erased! You have been warned!"
echo "Some commands require root permissions, you might be asked to enter your sudo password."

# use p1, p2 extentions instead of 1, 2 when using sd drives
if [[ $(echo $DEVICE_NODE | grep mmcblk) ]]; then
	BOOTPART="${DEVICE_NODE}p1"
	DATAPART="${DEVICE_NODE}p2"
else
	BOOTPART="${DEVICE_NODE}1"
	DATAPART="${DEVICE_NODE}2"
fi

# Creating EXT4 file system
echo -e "\e[1mCreating EXT4 file system...\e[0m"
for PARTITION in $(ls ${DEVICE_NODE}*)
do
    echo "Unmounting $PARTITION"
    sudo umount $PARTITION
done
sudo parted $DEVICE_NODE mklabel msdos --script
sudo parted $DEVICE_NODE mkpart primary ext4 1MB 250MB --script
sudo parted $DEVICE_NODE mkpart primary ext4 250MB 100% --script
sudo mkfs.ext4 -F -L boot $BOOTPART # 1st partition = boot
sudo mkfs.ext4 -F -L data $DATAPART # 2nd partition = data

# Flashing u-boot
echo -e "\e[1mFlashing U-boot...\e[0m"
unzip "${UBOOT_JOB}.zip"
sudo dd if="./u-boot-bootloader/u-boot/u-boot-sunxi-with-spl.bin" of="$DEVICE_NODE" bs=8k seek=1
sync

# Flashing rootFS
echo -e "\e[1mFlashing rootFS...\e[0m"
unzip "${ROOTFS_JOB}.zip"
TEMP=`ls $ROOTFS_DIR/*/*.tar.bz2`
echo "$TEMP"
mkdir "$MOUNT_DATA"
sudo mount $DATAPART "$MOUNT_DATA" # Mount data partition
sudo tar -xpf "$TEMP" -C "$MOUNT_DATA"
sync

# Copying kernel to boot partition
echo -e "\e[1mCopying kernel to boot partition...\e[0m"
mkdir "$MOUNT_BOOT"
sudo mount $BOOTPART "$MOUNT_BOOT" # Mount boot partition
sudo cp $MOUNT_DATA/boot/* $MOUNT_BOOT
sudo cp "./u-boot-bootloader/$ROOTFS_DIR/boot.scr" "$MOUNT_BOOT/boot.scr"
sync

# Clean up files
echo -e "\e[1mCleaning up!\e[0m"
for PARTITION in $(ls ${DEVICE_NODE}*)
do
    echo "Unmounting $PARTITION"
    sudo umount $PARTITION
done
rm "${UBOOT_JOB}.zip"
rm -r "$UBOOT_DIR"
rm "${ROOTFS_JOB}.zip"
rm -r "$ROOTFS_DIR"
rm -rf "$MOUNT_DATA"
rm -rf "$MOUNT_BOOT"

# Done :)
echo -e "\e[1mFlashing $DEVICE_NODE OK!\e[0m"
echo "You may now remove the SD card and insert it in your Pine64 device!"
