#!/usr/bin/env bash

if ! [ $(id -u) = 0 ]; then
   echo "Script must be run as root!"
   exit 1
fi

if ! [ -e ./floppy.img ]; then
    if [ -e ./out/floppyboot.bin ]; then
        # create raw floppy image
        dd if=/dev/zero of=./floppy.img bs=512 count=2880

        # get next loop device and mount it
        ld=$(losetup -f)
        losetup -b 512 $ld ./floppy.img

        # create FAT12 filesystem on image
        mkfs.fat $ld

        # copy MBR to floppy image, and overwrite generated FAT info
        dd if=./out/floppyboot.bin of=$ld bs=512

        # copy stage2 bootloader to floppy image
        if ! [ -e /tmp/cboot-floppy ]; then
            mkdir /tmp/cboot-floppy
        fi
        mount $ld /tmp/cboot-floppy
        cp -v ./out/OSLOADER.BIN /tmp/cboot-floppy/
        cp -v ./out/BOOTTEST.BIN /tmp/cboot-floppy/
        umount /tmp/cboot-floppy

        # detach loop device
        losetup -d $ld

        # chown to the real user to prevent issues with reading/writing the file later
        SUDOUSER=$(logname)
        chown --from=root:root ${SUDOUSER}:$(id $SUDOUSER -g) ./floppy.img

    else
        echo "unable to find assembled all required boot files! please run build.sh first"
        exit 2
    fi
else
    echo "A floppy image is already present, remove the old image or use update-mbr.sh instead"
    exit 3
fi