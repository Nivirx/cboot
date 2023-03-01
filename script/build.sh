#!/usr/bin/env bash

if [ -e ./out/floppyboot.bin ]; then
    rm -v ./out/floppyboot.bin
fi

if [ -e ./out/OSLOADER.BIN ]; then
    rm -v ./out/OSLOADER.BIN
fi

if [ -e ./out/BOOTTEST.BIN ]; then
    rm -v ./out/BOOTTEST.BIN
fi

echo "Building stage1..."
nasm -Wall -f bin -D DEBUG_HACK -o ./out/floppyboot.bin ./src/floppyboot.S

echo "Building stage2..."
nasm -Wall -f bin -D DEBUG_HACK -o ./out/OSLOADER.BIN ./src/osloader.S

echo "Building BOOTTEST.BIN"
nasm -Wall -f bin -D DEBUG_HACK -o ./out/BOOTTEST.BIN ./src/miniboot/boot32.S

if [ -e ./out/floppyboot.bin ] && [ -e ./out/OSLOADER.BIN ] && [ -e ./out/BOOTTEST.BIN ]; then
    echo "Build complete!"
else
    echo "Build failed!"
fi
