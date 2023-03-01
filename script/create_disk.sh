#!/usr/bin/env bash

if ! [ $(id -u) = 0 ]; then
   echo "Script must be run as root!"
   exit 1
fi

if ! [ -e ./floppy.img ]; then
    if [ -e ./out/floppyboot.bin ]; then
        # create raw disk image with 128MiB of space
        dd if=/dev/zero of=./disk.img bs=512 count=262144

        # get next loop device and mount it
        ld=$(losetup -f)
        losetup -b 512 $ld ./disk.img

        # create FAT12 filesystem on image
        mkfs.fat -F $ld

        # copy MBR to disk image, and overwrite generated FAT info
        dd if=./out/diskboot.bin of=$ld bs=512

        # copy stage2 bootloader to disk image
        if ! [ -e /tmp/cboot-disk ]; then
            mkdir /tmp/cboot-disk
        fi
        mount $ld /tmp/cboot-disk
        cp -v ./out/OSLOADER.BIN /tmp/cboot-disk/
        cp -v ./out/BOOTTEST.BIN /tmp/cboot-disk/
        umount /tmp/cboot-disk

        # detach loop device
        losetup -d $ld

        # chown to the real user to prevent issues with reading/writing the file later
        SUDOUSER=$(logname)
        chown --from=root:root ${SUDOUSER}:$(id $SUDOUSER -g) ./disk.img

    else
        echo "unable to find assembled all required boot files! please run build.sh first"
        exit 2
    fi
else
    echo "A floppy image is already present, remove the old image or use update-mbr.sh instead"
    exit 3

