#!/bin/bash
# Build the stereoscopic test .3dsx directly (no template Makefile) inside the
# devkitpro/devkitarm container. Compiles main.c against libctru and packs the
# ELF into a .3dsx with 3dsxtool.
set -e
: "${DEVKITPRO:=/opt/devkitpro}"
: "${DEVKITARM:=/opt/devkitpro/devkitARM}"
export PATH="$DEVKITARM/bin:$DEVKITPRO/tools/bin:$PATH"

ARCH="-march=armv6k -mtune=mpcore -mfloat-abi=hard -mtp=soft"
cd /work

arm-none-eabi-gcc $ARCH -mword-relocations -ffunction-sections -fdata-sections \
    -O2 -std=gnu11 -D__3DS__ \
    -I"$DEVKITPRO/libctru/include" \
    -specs="$DEVKITARM/arm-none-eabi/lib/3dsx.specs" \
    source/main.c \
    -L"$DEVKITPRO/libctru/lib" -lctru -lm \
    -o stereo_test.elf

3dsxtool stereo_test.elf stereo_test.3dsx
ls -la stereo_test.elf stereo_test.3dsx
echo "BUILD-OK"
