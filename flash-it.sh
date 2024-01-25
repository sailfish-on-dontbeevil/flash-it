#!/bin/bash

VERSION="0.4.0"
BRANCH=master
CUSTOM=""

ROOTFS_PINEPHONE_1_0_JOB=pinephone-1.0-rootfs
ROOTFS_PINEPHONE_1_1_JOB=pinephone-1.1-rootfs
ROOTFS_PINETAB_JOB=pinetab-rootfs
ROOTFS_PINETABDEV_JOB=pinetab-rootfs
ROOTFS_PINEPHONEPRO_JOB=pinephonepro-rootfs
ROOTFS_PINETAB2_JOB=pinetab2-rootfs

ROOTFS_PINEPHONE_1_0_DIR=pinephone-1.0
ROOTFS_PINEPHONE_1_1_DIR=pinephone-1.1
ROOTFS_PINETAB_DIR=pinetab
ROOTFS_PINETABDEV_DIR=pinetab
ROOTFS_PINEPHONEPRO_DIR=pinephonepro
ROOTFS_PINETAB2_DIR=pinetab2

UBOOT_PINEPHONE_1_0_FILE=boot.pinephone10.scr
UBOOT_PINEPHONE_1_1_FILE=boot.pinephone11.scr
UBOOT_PINETAB_FILE=boot.pinetab.scr
UBOOT_PINETABDEV_FILE=boot.pinetabdev.scr
UBOOT_PINEPHONEPRO_FILE=boot.pinephonepro.scr
UBOOT_PINETAB2_FILE=boot.pinetab2.scr

MOUNT_ROOT=./root
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

# Add sbin to the PATH to check for commands available to sudo
function check_sudo_dependency {
    dependency=$1
    local PATH=$PATH:/sbin:/usr/sbin:/usr/local/sbin
    check_dependency $dependency
}

# Determine if wget supports the --show-progress option (introduced in
# 1.16). If so, make use of that instead of spewing out redirects and
# loads of info into the terminal.
function wget_cmd {
    #wget --show-progress > /dev/null 2>&1
    #status=$?

    # Exit code 2 means command parsing error (i.e. option does not
    # exist).
    #if [ "$status" == "2" ]; then
        echo "wget -O"
    #else
        #echo "wget -q --show-progress -O"
    #fi
}

# Check dependencies
check_dependency "sudo"
check_dependency "wget"
check_dependency "tar"
check_dependency "unzip"
check_dependency "lsblk"
check_dependency "jq"
check_sudo_dependency "parted"
check_sudo_dependency "mkfs.ext4"
check_sudo_dependency "losetup"
check_sudo_dependency "sfdisk"

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
echo "========================================"
echo ""
echo "NOTE: Before continuing installation, please ensure you have TowBoot installed on your device"
echo "See https://tow-boot.org/devices/index.html for guidance on installation"
echo "This script has been tested with Towboot installed on the Pinephone EMMC and PinephonePro SPI"
echo ""


# Image selection
echo -e "\e[1mWhich image do you want to flash?\e[0m"
select OPTION in "PinePhone 1.0 (Development) device" "PinePhone 1.1 (Brave Heart) or 1.2 (Community Editions) device" "PineTab device" "PineTab Dev device" "Pinephone Pro" "Pinetab 2"; do
    case $OPTION in
        "PinePhone 1.0 (Development) device" ) ROOTFS_JOB=$ROOTFS_PINEPHONE_1_0_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONE_1_0_DIR; UBOOT_FILE=$UBOOT_PINEPHONE_1_0_FILE; break;;
        "PinePhone 1.1 (Brave Heart) or 1.2 (Community Editions) device" ) ROOTFS_JOB=$ROOTFS_PINEPHONE_1_1_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONE_1_1_DIR; UBOOT_FILE=$UBOOT_PINEPHONE_1_1_FILE; break;;
        "PineTab device" ) ROOTFS_JOB=$ROOTFS_PINETAB_JOB; ROOTFS_DIR=$ROOTFS_PINETAB_DIR; UBOOT_FILE=$UBOOT_PINETAB_FILE; break;;
        "PineTab Dev device" ) ROOTFS_JOB=$ROOTFS_PINETABDEV_JOB; ROOTFS_DIR=$ROOTFS_PINETABDEV_DIR; UBOOT_FILE=$UBOOT_PINETABDEV_FILE; break;;
        "Pinephone Pro" ) ROOTFS_JOB=$ROOTFS_PINEPHONEPRO_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONEPRO_DIR; UBOOT_FILE=$UBOOT_PINEPHONEPRO_FILE; break;;
        "Pinetab 2" ) ROOTFS_JOB=$ROOTFS_PINETAB2_JOB; ROOTFS_DIR=$ROOTFS_PINETAB2_DIR; UBOOT_FILE=$UBOOT_PINETAB2_FILE; break;;
    esac
done

# Downloading images
echo -e "\e[1mDownloading images...\e[0m"
WGET=$(wget_cmd)

ROOTFS_DOWNLOAD="https://gitlab.com/sailfishos-porters-ci/dont_be_evil-ci/-/jobs/artifacts/$BRANCH/download?job=$ROOTFS_JOB"
echo $ROOTFS_DOWNLOAD
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

#Delete all partitions
sudo sfdisk --delete $DEVICE_NODE

#Create partitions
sudo parted $DEVICE_NODE mklabel msdos --script
sudo parted $DEVICE_NODE mkpart primary ext4 32MB 256MB --script
sudo parted $DEVICE_NODE mkpart primary ext4 256MB 8192MB --script
#Create a 3rd partition for home.  Community encryption will format it.
sudo parted $DEVICE_NODE mkpart primary ext4 8192MB 100% --script

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
	ROOTPART="${DEVICE_NODE}p2"
	HOMEPART="${DEVICE_NODE}p3"
else
	BOOTPART="${DEVICE_NODE}1"
	ROOTPART="${DEVICE_NODE}2"
	HOMEPART="${DEVICE_NODE}3"
fi

sudo mkfs.ext4 -F -L boot $BOOTPART # 1st partition = boot
sudo mkfs.ext4 -F -L root $ROOTPART # 2nd partition = root
sudo mkfs.ext4 -F -L home $HOMEPART # 3rd partition = home

# Flashing rootFS
echo -e "\e[1mFlashing rootFS...\e[0m"
mkdir "$MOUNT_ROOT"
if [ "$CUSTOM" != "" ]; then
    TEMP="${CUSTOM}/rootfs.tar.bz2"
else
    unzip "${ROOTFS_JOB}.zip"
    TEMP=`ls $ROOTFS_DIR/*/*.tar.bz2`
    echo "$TEMP"
fi
sudo mount $ROOTPART "$MOUNT_ROOT" # Mount root partition
sudo tar -xpf "$TEMP" -C "$MOUNT_ROOT"
sync

# Copying kernel to boot partition
echo -e "\e[1mCopying kernel to boot partition...\e[0m"
mkdir "$MOUNT_BOOT"
sudo mount $BOOTPART "$MOUNT_BOOT" # Mount boot partition
echo "Boot partition mount: $MOUNT_BOOT"
sudo sh -c "cp -r $MOUNT_ROOT/boot/* $MOUNT_BOOT"


#Only copy boot script if not Pinetab2
if [ "$OPTION" != "Pinetab 2" ]; then
    echo `ls $MOUNT_BOOT`
    echo -e "\e[1mCopying UBoot script to boot partition...\e[0m"
    if [ "$CUSTOM" != "" ]; then
        sudo sh -c "cp '${CUSTOM}/boot.scr' '$MOUNT_BOOT/boot.scr'"
    else
        sudo sh -c "cp '$MOUNT_BOOT/$UBOOT_FILE' '$MOUNT_BOOT/boot.scr'"
    fi
    sync
else
    #Flash the uboot supplied with the release
    if [ -f "$MOUNT_BOOT/u-boot-rockchip.bin" ]; then
        read -p "Do you want to flash uboot? " yn
        case $yn in
            [Yy]* ) sudo dd if="$MOUNT_BOOT/u-boot-rockchip.bin" of="${DEVICE_NODE}" oflag=direct seek=64
        esac
    fi
    #Rewrite the boot config
    PARTUUID=`sudo blkid $ROOTPART -s PARTUUID -o value`
    sed "s/ROOTUUID/$PARTUUID/" $MOUNT_BOOT/extlinux/extlinux.conf.in | sudo tee $MOUNT_BOOT/extlinux/extlinux.conf > /dev/null;
fi

#Rewrite the home config
read -p "Are you installing to an SD card? " yn
if [ "$OPTION" == "Pinephone Pro" ]; then
    DEVICESD="mmcblk1"
else
    DEVICESD="mmcblk0"
fi
case $yn in
	[Yy]* ) sudo sed -i "s/mmcblk2/$DEVICESD/" $MOUNT_ROOT/etc/sailfish-device-encryption-community/devices.ini;
esac

read -p "Clear root password? " yn
case $yn in
	[Yy]* ) sudo sed -i '0,/:!:/{s/:!:/::/}' $MOUNT_ROOT/etc/shadow;
esac

# Clean up files
echo -e "\e[1mCleaning up!\e[0m"
for PARTITION in $(ls ${DEVICE_NODE}*)
do
    echo "Unmounting $PARTITION"
    sudo umount $PARTITION
done

sudo losetup -D

if [ "$CUSTOM" == "" ]; then
    rm "${ROOTFS_JOB}.zip"
    rm -r "$ROOTFS_DIR"
fi
sudo rm -rf "$MOUNT_ROOT"
sudo rm -rf "$MOUNT_BOOT"

# Done :)
echo -e "\e[1mFlashing $DEVICE_NODE OK!\e[0m"
echo "You may now remove the SD card and insert it in your Pine64 device!"
