#!/bin/sh

VERSION="0.3.3"
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
unset POSITIONAL
while [ "$#" -gt 0 ]; do
	case "$1" in
		-b|--branch)
			BRANCH="$2"
			shift 2
			;;
		-h|--help)
			printf '%s\n'  "Sailfish OS flashing script for Pine64 devices
This script will download the latest Sailfish OS image for the Pine
Phone, Pine Phone dev kit, or Pine Tab. It requires that you have a
micro SD card inserted into the computer.

usage: flash-it.sh [-b BRANCH]

Options:

-c, --custom Install from custom dir. Just put you rootfs.tar.bz2
             and u-boot-sunxi-with-spl.bin into dir and system will
             istalled from it
-b, --branch BRANCH	Download images from a specific Git branch.
-h, --help   Print this help and exit.

This command requires: parted; sudo, doas or su; wget or curl; tar, unzip, lsblk,
and mkfs.ext4.

Some distros do not have parted on the PATH. If necessary, add
parted to the PATH before running the script."
			exit 0
			;;
		-c|--custom)
			CUSTOM="$2"
			shift 2
			;;
		*) # unknown argument
			POSITIONAL="$POSITIONAL:$1" # save it in a list for later
			shift # past argument
			;;
	esac
done
# Retrieve saved arguments
IFS=: set -- ${POSITIONAL#:}

# Helper functions

# Run as root
as_root() {
	command -V sudo >/dev/null 2>&1 && {
		sudo "$@"
		return "$?"
	}
	command -V doas >/dev/null 2>&1 && {
		doas "$@"
		return "$?"
	}
	command -V su >/dev/null 2>&1 && {
		su -c "$*"
		return "$?"
	}
}

# Print message to stderr and exit
die() {
	printf '%s\n' "$*" >&2
	exit "${status:-2}"
}
# Error out if the given command is not found on the PATH.
check_dependency() {
    command -V "$1" >/dev/null 2>&1 ||
        status=1 die "$1 not found. Please make sure it is installed and in your PATH."
}

# Check if one or more of depends are present
check_alternative_dependencies() {
	IFS=', ' all="$*"
	unset found
	while [ "$1" ]; do
		command -V "$1" >/dev/null 2>&1 && {
			found=y
			break
		}
		shift
	done

	[ "$found" ] || die "None of '$all found'. Please make sure one of them is installed and in your PATH."
}

# Determine if wget supports the --show-progress option (introduced in
# 1.16). If so, make use of that instead of spewing out redirects and
# loads of info into the terminal.
set_wget_cmd() {
	if command -V wget >/dev/null 2>&1; then

		if wget --help 2>&1 | grep -q 'show-progress'; then
			WGET="wget -q --show-progress -O"
		else
			WGET="wget -O"
		fi

	else
		WGET="curl -Lo"
	fi
}

# Add sbin to the PATH to make sure all commands are found
export PATH="$PATH:/sbin:/usr/sbin:/usr/local/sbin"
# Check dependencies
check_alternative_dependencies sudo doas su
check_alternative_dependencies wget curl
check_dependency tar
check_dependency unzip
check_dependency lsblk
check_dependency parted
check_dependency mkfs.ext4
check_dependency losetup

# If use custom dir check it
if [ "$CUSTOM" ]; then
	if [ ! -d "$CUSTOM" ]; then
		die "[1m[97m!!! Directory $CUSTOM not exist !!![0m"
	fi

	if [ ! -f "$CUSTOM/rootfs.tar.bz2" ]; then
		die "[1m[97m!!! rootfs $CUSTOM/rootfs.tar.bz2 not found !!![0m"
	fi

	if [ ! -f "$CUSTOM/u-boot-sunxi-with-spl.bin" ]; then
		die "[1m[97m!!! uboot image $CUSTOM/u-boot-sunxi-with-spl.bin not found !!![0m"
	fi

	if ! [ -f "$CUSTOM/boot.scr" ]; then
		die "[1m[97m!!! uboot config $CUSTOM/boot.scr not found !!![0m"
	fi
else
	# Different branch for some reason?
	if [ "$BRANCH" != "master" ]; then
		printf '%s\n' "[1m[97m!!! Will flash image from ${BRANCH} branch !!![0m"
	fi

	# Header
	printf '%s\n' "[1m[91mSailfish OS Pine64 device flasher V$VERSION[0m
======================================
"

	# Image selection
	printf '%s\n' "[1mWhich image do you want to flash?[0m"

	: $(( i = 0 ))
	for opt in "PinePhone 1.0 (Development) device" "PinePhone 1.1 (Brave Heart) device" "PineTab device" "PineTab Dev device" "Dont Be Evil devkit"; do
		: $(( i += 1 ))
		printf '%s\n' "$i) $opt"
	done
	printf '%s' "#? "
	read -r OPTION

	case "$OPTION" in
		1) ROOTFS_JOB=$ROOTFS_PINEPHONE_1_0_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONE_1_0_DIR; UBOOT_DEV_DIR=$UBOOT_PINEPHONE_1_0_DIR;;
		2) ROOTFS_JOB=$ROOTFS_PINEPHONE_1_1_JOB; ROOTFS_DIR=$ROOTFS_PINEPHONE_1_1_DIR; UBOOT_DEV_DIR=$UBOOT_PINEPHONE_1_1_DIR;;
		3) ROOTFS_JOB=$ROOTFS_PINETAB_JOB; ROOTFS_DIR=$ROOTFS_PINETAB_DIR; UBOOT_DEV_DIR=$UBOOT_PINETAB_DIR;;
		4) ROOTFS_JOB=$ROOTFS_PINETABDEV_JOB; ROOTFS_DIR=$ROOTFS_PINETABDEV_DIR; UBOOT_DEV_DIR=$UBOOT_PINETABDEV_DIR;;
		5) ROOTFS_JOB=$ROOTFS_DEVKIT_JOB; ROOTFS_DIR=$ROOTFS_DEVKIT_DIR; UBOOT_DEV_DIR=$UBOOT_DEVKIT_DIR;;
		*) die "Invalid selection";;
	esac

	# Downloading images
	printf '%s\n' "[1mDownloading images...[0m"
	set_wget_cmd
	UBOOT_DOWNLOAD="https://gitlab.com/sailfishos-porters-ci/dont_be_evil-ci/-/jobs/artifacts/$BRANCH/download?job=$UBOOT_JOB"
	$WGET "$UBOOT_JOB.zip" "$UBOOT_DOWNLOAD" || {
		die "UBoot image download failed. Aborting."
	}

	UBOOT2_JOB=u-boot-sunxi-with-spl-pinephone.bin
	UBOOT_DOWNLOAD2="https://gitlab.com/pine64-org/crust-meta/-/jobs/artifacts/master/raw/u-boot-sunxi-with-spl-pinephone.bin?job=build"
	$WGET "$UBOOT2_JOB" "$UBOOT_DOWNLOAD2" || {
		die "UBoot image download failed. Aborting."
	}

	ROOTFS_DOWNLOAD="https://gitlab.com/sailfishos-porters-ci/dont_be_evil-ci/-/jobs/artifacts/$BRANCH/download?job=$ROOTFS_JOB"
	$WGET "$ROOTFS_JOB.zip" "$ROOTFS_DOWNLOAD" || {
		die "Root filesystem image download failed. Aborting."
	}
fi

# Select flash target
printf '%s\n' "[1mWhich SD card do you want to flash?[0m"
lsblk
printf '%s\n%s\n' "raw" "Device node (/dev/sdX): "
read -r DEVICE_NODE
printf '%s\n' "Flashing image to: $DEVICE_NODE
WARNING: All data will be erased! You have been warned!
Some commands require root permissions, you might be asked to enter your password."

#create loop file for raw.img
if [ "$DEVICE_NODE" = raw ]; then
	as_root dd if=/dev/zero of=sdcard.img bs=1 count=0 seek=4G
	DEVICE_NODE=./sdcard.img
fi

# Creating EXT4 file system
printf '%s\n' "[1mCreating EXT4 file system...[0m"
for PARTITION in "$DEVICE_NODE"*; do
    echo "Unmounting $PARTITION"
    as_root umount "$PARTITION"
done
as_root parted "$DEVICE_NODE" mklabel msdos --script
as_root parted "$DEVICE_NODE" mkpart primary ext4 1MB 250MB --script
as_root parted "$DEVICE_NODE" mkpart primary ext4 250MB 100% --script

if [ "$DEVICE_NODE" = ./sdcard.img ]; then
	printf '%s\n' "Prepare loop file"
	as_root losetup -D
	as_root losetup -Pf sdcard.img
	LOOP_NODE="$(echo /dev/loop?p1 | cut -c10-10)"
	DEVICE_NODE="/dev/loop$LOOP_NODE"
fi

# use p1, p2 extentions instead of 1, 2 when using sd drives
if echo "$DEVICE_NODE" | grep -q -E 'mmcblk|loop'; then
	BOOTPART="${DEVICE_NODE}p1"
	DATAPART="${DEVICE_NODE}p2"
else
	BOOTPART="${DEVICE_NODE}1"
	DATAPART="${DEVICE_NODE}2"
fi

as_root mkfs.ext4 -F -L boot "$BOOTPART" # 1st partition = boot
as_root mkfs.ext4 -F -L data "$DATAPART" # 2nd partition = data

# Flashing u-boot
printf '%s\n' "[1mFlashing U-boot...[0m"
if [ "$CUSTOM" ]; then
	as_root dd if="$CUSTOM/u-boot-sunxi-with-spl.bin" of="$DEVICE_NODE" bs=8k seek=1
else
	unzip "$UBOOT_JOB.zip"
	as_root dd if="./u-boot-sunxi-with-spl-pinephone.bin" of="$DEVICE_NODE" bs=8k seek=1
fi
sync

# Flashing rootFS
printf '%s\n' "[1mFlashing rootFS...[0m"
mkdir "$MOUNT_DATA"
if [ "$CUSTOM" ]; then
    TEMP="$CUSTOM/rootfs.tar.bz2"
else
    unzip "$ROOTFS_JOB.zip"
	TEMP="$(echo $ROOTFS_DIR/*/*.tar.bz2)"
    echo "$TEMP"
fi
as_root mount "$DATAPART" "$MOUNT_DATA" # Mount data partition
as_root tar -xpf "$TEMP" -C "$MOUNT_DATA"
sync

# Copying kernel to boot partition
printf '%s\n' "[1mCopying kernel to boot partition...[0m"
mkdir "$MOUNT_BOOT"
as_root mount "$BOOTPART" "$MOUNT_BOOT" # Mount boot partition
printf '%s\n' "Boot partition mount: $MOUNT_BOOT"
as_root cp -r "$MOUNT_DATA/boot"/* "$MOUNT_BOOT"

echo "$MOUNT_BOOT"
if [ "$CUSTOM" ]; then
    as_root cp "$CUSTOM/boot.scr" "$MOUNT_BOOT/boot.scr"
else
    as_root cp "./u-boot-bootloader/$UBOOT_DEV_DIR/boot.scr" "$MOUNT_BOOT/boot.scr"
fi
sync

# Clean up files
printf '%s\n' "[1mCleaning up![0m"
for PARTITION in "$DEVICE_NODE"*; do
    echo "Unmounting $PARTITION"
    as_root umount "$PARTITION"
done

as_root losetup -D

if [ -z "$CUSTOM" ]; then
    rm -r "$UBOOT_JOB.zip" "$UBOOT2_JOB" "$UBOOT_DIR" "$ROOTFS_JOB.zip" "$ROOTFS_DIR"
fi
as_root rm -rf "$MOUNT_DATA" "$MOUNT_BOOT"

# Done :)
printf '%s\n' "[1mFlashing $DEVICE_NODE OK![0m
You may now remove the SD card and insert it in your Pine64 device!"
