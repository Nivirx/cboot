#!/usr/bin/env bash

if ! [ $(id -u) = 0 ]; then
   echo "Script must be run as root!"
   exit 1
fi

if [ -e ./floppy.img ] && [ -e ./out/floppyboot.bin ]; then
    # get next loop device and mount it
    ld=$(losetup -f)
    losetup $ld ./floppy.img

    # copy MBR to floppy image
    dd if=./out/floppyboot.bin of=$ld bs=512

    # copy stage2 bootloader to floppy image
        if ! [ -e /tmp/cboot-floppy ]; then
            mkdir /tmp/cboot-floppy
        fi
        
        mount $ld /tmp/cboot-floppy

        if [ -e /tmp/cboot-floppy/OSLOADER.BIN ]; then
            rm -v /tmp/cboot-floppy/*.BIN
            cp -v ./out/OSLOADER.BIN /tmp/cboot-floppy/
            cp -v ./out/BOOTTEST.BIN /tmp/cboot-floppy/
        fi

        umount /tmp/cboot-floppy

    # detach loop device
    losetup -d $ld
else
    echo "missing either floppy.img or ./out/floppyboot.bin"
    exit 2
fi