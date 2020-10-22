#!/bin/bash

VERSION="0.3.2"
BRANCH=master
CUSTOM=""
UBOOT_JOB=u-boot
UBOOT_DIR=u-boot-bootloader

ROOTFS_PINEPHONE_1_0_JOB=pinephone-1.0-rootfs
ROOTFS_PINEPHONE_1_1_JOB=pinephone-1.1-rootfs
ROOTFS_PINETAB_JOB=pinetab-rootfs
ROOTFS_PINETABDEV_JOB=pinetab-rootfs
ROOTFS_DEVKIT_JOB=devkit-rootfs
ROOTFS_PINEPHONE_1_0_DIR=pinephone-1.0
ROOTFS_PINEPHONE_1_1_DIR=pinephone-1.1
ROOTFS_PINETAB_DIR=pinetab
ROOTFS_PINETABDEV_DIR=pinetab
ROOTFS_DEVKIT_DIR=devkit

UBOOT_PINEPHONE_1_0_DIR=pinephone-1.0
UBOOT_PINEPHONE_1_1_DIR=pinephone-1.1
UBOOT_PINETAB_DIR=pinetab
UBOOT_PINETABDEV_DIR=pinetabdev
UBOOT_DEVKIT_DIR=devkit

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
               "	-c, --custom		Install from custom dir. Just put you rootfs.tar.bz2" \
               "				and u-boot-sunxi-with-spl.bin into dir and system will "\
               "				istalled from it" \
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
	-c|--custom)
		CUSTOM="$2"
		shift
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
check_dependency "losetup"

# If use custom dir check it
if [ "$CUSTOM" != "" ]; then
	if ! [ -d "$CUSTOM" ]; then
		echo -e "\e[1m\e[97m!!! Directory ${CUSTOM} not exist !!!\e[0m"
		exit 2;
	fi

	if ! [ -f "$CUSTOM/rootfs.tar.bz2" ]; then
		echo -e "\e[1m\e[97m!!! rootfs ${CUSTOM}/rootfs.tar.bz2 not found !!!\e[0m"
		exit 2;
	fi

	if ! [ -f "$CUSTOM/u-boot-sunxi-with-spl.bin" ]; then
		echo -e "\e[1m\e[97m!!! uboot image ${CUSTOM}/u-boot-sunxi-with-spl.bin not found !!!\e[0m"
		exit 2;
	fi

	if ! [ -f "$CUSTOM/boot.scr" ]; then
		echo -e "\e[1m\e[97m!!! uboot config ${CUSTOM}/boot.scr not found !!!\e[0m"
		exit 2;
	fi
else
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
select OPTION in "PinePhone 1.0 (Development) device" "PinePhone 1.1 (Brave Heart) device" "PineTab device" "PineTab Dev device" "Dont Be Evil devkit"; do
    case $OPTION in
        "PinePhone 1.0 (Development) device" ) ROOTFS_JOB=$ROOTFS_PINEPHONE_1_0_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONE_1_0_DIR; UBOOT_DEV_DIR=$UBOOT_PINEPHONE_1_0_DIR; break;;
        "PinePhone 1.1 (Brave Heart) device" ) ROOTFS_JOB=$ROOTFS_PINEPHONE_1_1_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONE_1_1_DIR; UBOOT_DEV_DIR=$UBOOT_PINEPHONE_1_1_DIR; break;;
        "PineTab device" ) ROOTFS_JOB=$ROOTFS_PINETAB_JOB; ROOTFS_DIR=$ROOTFS_PINETAB_DIR; UBOOT_DEV_DIR=$UBOOT_PINETAB_DIR; break;;
        "PineTab Dev device" ) ROOTFS_JOB=$ROOTFS_PINETABDEV_JOB; ROOTFS_DIR=$ROOTFS_PINETABDEV_DIR; UBOOT_DEV_DIR=$UBOOT_PINETABDEV_DIR; break;;
        "Dont Be Evil devkit" ) ROOTFS_JOB=$ROOTFS_DEVKIT_JOB; ROOTFS_DIR=$ROOTFS_DEVKIT_DIR; UBOOT_DEV_DIR=$UBOOT_DEVKIT_DIR; break;;
    esac
done

# Downloading images
echo -e "\e[1mDownloading images...\e[0m"
WGET=$(wget_cmd)
UBOOT_DOWNLOAD="https://gitlab.com/sailfishos-porters-ci/dont_be_evil-ci/-/jobs/artifacts/$BRANCH/download?job=$UBOOT_JOB"
$WGET "${UBOOT_JOB}.zip" "${UBOOT_DOWNLOAD}" || {
	echo >&2 "UBoot image download failed. Aborting."
	exit 2
}

ROOTFS_DOWNLOAD="https://gitlab.com/sailfishos-porters-ci/dont_be_evil-ci/-/jobs/artifacts/$BRANCH/download?job=$ROOTFS_JOB"
$WGET "${ROOTFS_JOB}.zip" "${ROOTFS_DOWNLOAD}" || {
	echo >&2 "Root filesystem image download failed. Aborting."
	exit 2
}
fi

# Select flash target
echo -e "\e[1mWhich SD card do you want to flash?\e[0m"
lsblk
echo "raw"
read -p "Device node (/dev/sdX): " DEVICE_NODE
echo "Flashing image to: $DEVICE_NODE"
echo "WARNING: All data will be erased! You have been warned!"
echo "Some commands require root permissions, you might be asked to enter your sudo password."

#create loop file for raw.img
if [ $DEVICE_NODE == "raw" ]; then
	sudo dd if=/dev/zero of=sdcard.img bs=1 count=0 seek=4G
	DEVICE_NODE="./sdcard.img"
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

if [ $DEVICE_NODE == "./sdcard.img" ]; then
	echo "Prepare loop file"
	sudo losetup -D
	sudo losetup -Pf sdcard.img
	LOOP_NODE=`ls /dev/loop?p1 | cut -c10-10`
	DEVICE_NODE="/dev/loop$LOOP_NODE"
fi

# use p1, p2 extentions instead of 1, 2 when using sd drives
if [ $(echo $DEVICE_NODE | grep mmcblk || echo $DEVICE_NODE | grep loop) ]; then
	BOOTPART="${DEVICE_NODE}p1"
	DATAPART="${DEVICE_NODE}p2"
else
	BOOTPART="${DEVICE_NODE}1"
	DATAPART="${DEVICE_NODE}2"
fi

sudo mkfs.ext4 -F -L boot $BOOTPART # 1st partition = boot
sudo mkfs.ext4 -F -L data $DATAPART # 2nd partition = data

# Flashing u-boot
echo -e "\e[1mFlashing U-boot...\e[0m"
if [ "$CUSTOM" != "" ]; then
sudo dd if="${CUSTOM}/u-boot-sunxi-with-spl.bin" of="$DEVICE_NODE" bs=8k seek=1
else
unzip "${UBOOT_JOB}.zip"
sudo dd if="./u-boot-bootloader/u-boot/u-boot-sunxi-with-spl.bin" of="$DEVICE_NODE" bs=8k seek=1
fi
sync

# Flashing rootFS
echo -e "\e[1mFlashing rootFS...\e[0m"
mkdir "$MOUNT_DATA"
if [ "$CUSTOM" != "" ]; then
    TEMP="${CUSTOM}/rootfs.tar.bz2"
else
    unzip "${ROOTFS_JOB}.zip"
    TEMP=`ls $ROOTFS_DIR/*/*.tar.bz2`
    echo "$TEMP"
fi
sudo mount $DATAPART "$MOUNT_DATA" # Mount data partition
sudo tar -xpf "$TEMP" -C "$MOUNT_DATA"
sync

# Copying kernel to boot partition
echo -e "\e[1mCopying kernel to boot partition...\e[0m"
mkdir "$MOUNT_BOOT"
sudo mount $BOOTPART "$MOUNT_BOOT" # Mount boot partition
echo "Boot partition mount: $MOUNT_BOOT"
sudo sh -c "cp -r $MOUNT_DATA/boot/* $MOUNT_BOOT"

echo `ls $MOUNT_BOOT`
if [ "$CUSTOM" != "" ]; then
    sudo sh -c "cp '${CUSTOM}/boot.scr' '$MOUNT_BOOT/boot.scr'"
else
    sudo sh -c "cp './u-boot-bootloader/$UBOOT_DEV_DIR/boot.scr' '$MOUNT_BOOT/boot.scr'"
fi
sync

# Clean up files
echo -e "\e[1mCleaning up!\e[0m"
for PARTITION in $(ls ${DEVICE_NODE}*)
do
    echo "Unmounting $PARTITION"
    sudo umount $PARTITION
done

sudo losetup -D

if [ "$CUSTOM" == "" ]; then
    rm "${UBOOT_JOB}.zip"
    rm -r "$UBOOT_DIR"
    rm "${ROOTFS_JOB}.zip"
    rm -r "$ROOTFS_DIR"
fi
sudo rm -rf "$MOUNT_DATA"
sudo rm -rf "$MOUNT_BOOT"

# Done :)
echo -e "\e[1mFlashing $DEVICE_NODE OK!\e[0m"
echo "You may now remove the SD card and insert it in your Pine64 device!"
