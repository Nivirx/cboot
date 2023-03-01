#!/usr/bin/env bash
if ! [ -e ./bin/bios.bin ]; then
    echo "unable to locate bios.bin in ./bin/, build a bios for QEMU and place it there"
    exit 1
fi

if ! [ -e ./floppy.img ]; then
    echo "unable to locate floppy.img, build it with './script/build.sh && sudo ./script/create_floppy.sh' "
    exit 2
fi

qemu-system-i386 -L ./bin/ -bios bios.bin -no-kvm -cpu pentium3 -m 64 -s -monitor stdio -drive file=./floppy.img,index=0,if=floppy,format=raw
