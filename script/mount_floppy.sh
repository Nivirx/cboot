#!/usr/bin/env bash

if ! [ $(id -u) = 0 ]; then
   echo "Script must be run as root!"
   exit 1
fi

if [ -e ./floppy.img ]; then
    # get next loop device and mount it
    ld=$(losetup -f)
    losetup -v -b 512 $ld ./floppy.img

    echo "Floppy image mounted on $ld..."
    echo "Dismount with 'losetup -d $ld && umount $ld' "
else
    echo "No floppy.img found!"
fi