#!/bin/bash
# SPDX-License-Identifier: MIT
# Pack an Android boot image for the Samsung Galaxy S4 (GT-I9505, "jflte").
#
# The S4's bootloader reads the image header, copies the "kernel" slot to BASE + KERNEL_OFFSET and the
# "ramdisk" slot to BASE + RAMDISK_OFFSET, and starts the kernel with the ATAGS at BASE + TAGS_OFFSET.
# The numbers are the ones LineageOS uses for this phone (BoardConfigCommon.mk of jf-common); they are
# read from apq8064.h next to this file so that there is one copy of them.
#
# What goes in the "kernel" slot is whatever should run first: a bare-metal test program, the S4 loader
# of this project, or a small Linux used as a launch pad (docs/s4-armv7-port.md, "Stages"). It is NOT the
# room for the iOS system image: the BOOT partition is 10 MiB (BOARD_BOOTIMAGE_PARTITION_SIZE in the
# same file), so the script refuses anything larger. How a big payload gets into RAM is in the document.
#
# usage: devices/galaxy-s4/mkbootimg.sh -o OUT.img --kernel FILE [--ramdisk FILE] [--cmdline STR]
#                                       [--max BYTES]
#   --max   size limit; default: the BOOT partition. RECOVERY's size has not been measured (VERIFY),
#           so a bigger image for that partition needs an explicit --max.
#
# Nothing here talks to a phone. Writing the image to a partition (Odin or Heimdall in Download mode)
# overwrites that partition, may trip the Knox warranty bit, and is the user's decision: README.md.
set -e
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)
MKBOOTIMG=${MKBOOTIMG:-$TOP/devices/poco-x5-pro/prebuilt/mkbootimg.py}   # AOSP's, Apache-2.0, shared by both devices
HDR=$HERE/apq8064.h

die() { echo "mkbootimg.sh: $*" >&2; exit 1; }

# value of `#define NAME <number>[u]` from apq8064.h (decimal or 0x hex)
def() {
	local v
	v=$(sed -n -E "s/^#define[[:space:]]+$1[[:space:]]+(0[xX][0-9a-fA-F]+|[0-9]+)[uU]?([[:space:]].*)?$/\1/p" "$HDR" | head -n1)
	[ -n "$v" ] || die "$1 is not defined in $HDR"
	echo "$v"
}

OUT= KERNEL= RAMDISK= CMDLINE= MAX=
while [ $# -gt 0 ]; do
	case "$1" in
	-o|--output)  OUT=$2; shift 2 ;;
	--kernel)     KERNEL=$2; shift 2 ;;
	--ramdisk)    RAMDISK=$2; shift 2 ;;
	--cmdline)    CMDLINE=$2; shift 2 ;;
	--max)        MAX=$2; shift 2 ;;
	-h|--help)    sed -n '3,/^set -e/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
	*)            die "unknown argument: $1 (try --help)" ;;
	esac
done
[ -n "$OUT" ] && [ -n "$KERNEL" ] || die "usage: $0 -o OUT.img --kernel FILE [--ramdisk FILE] [--cmdline STR] [--max BYTES]"
[ -f "$KERNEL" ] || die "no such file: $KERNEL"
[ -z "$RAMDISK" ] || [ -f "$RAMDISK" ] || die "no such file: $RAMDISK"
[ -f "$MKBOOTIMG" ] || die "mkbootimg.py not found at $MKBOOTIMG"
[ -f "$HDR" ] || die "$HDR not found"

BASE=$(def S4_BOOT_BASE)
KOFF=$(def S4_BOOT_KERNEL_OFFSET)
ROFF=$(def S4_BOOT_RAMDISK_OFFSET)
TOFF=$(def S4_BOOT_TAGS_OFFSET)
PAGE=$(def S4_BOOT_PAGE_SIZE)
: "${MAX:=$(def S4_BOOT_PARTITION_MAX)}"

args=(--kernel "$KERNEL" --base "$BASE" --kernel_offset "$KOFF" --ramdisk_offset "$ROFF"
      --tags_offset "$TOFF" --pagesize "$PAGE" --header_version 0 --board jflte --cmdline "$CMDLINE"
      -o "$OUT")
[ -z "$RAMDISK" ] || args+=(--ramdisk "$RAMDISK")
python3 "$MKBOOTIMG" "${args[@]}"

size=$(stat -c %s "$OUT" 2>/dev/null || stat -f %z "$OUT")
if [ "$size" -gt "$((MAX))" ]; then
	rm -f "$OUT"
	die "$size bytes is over the limit of $((MAX)) bytes (the BOOT partition is 10 MiB); removed $OUT. Pass --max only for a partition you have measured."
fi
echo "mkbootimg.sh: $OUT: $size bytes (limit $((MAX))); kernel at $(printf '0x%08x' $((BASE + KOFF))), ramdisk at $(printf '0x%08x' $((BASE + ROFF))), tags at $(printf '0x%08x' $((BASE + TOFF))), page $PAGE"
