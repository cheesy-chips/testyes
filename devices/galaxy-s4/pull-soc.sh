#!/bin/bash
# SPDX-License-Identifier: MIT
# Ask a Galaxy S4 (GT-I9505, "jflte") running Android what it is, over adb, and write down the facts
# the port needs that no document gives: the Krait's ID registers and feature flags, the RAM map, the
# framebuffer, the size of every partition. It settles the lines marked VERIFY in apq8064.h.
#
# The S4's Android kernel is a board-file kernel, so unlike the POCO X5 Pro there is no device tree on the
# phone to read (compare devices/poco-x5-pro/pull-soc.sh). What it does have is /proc and /sys.
#
# usage: devices/galaxy-s4/pull-soc.sh [-s SERIAL] [-o DIR]
#   -s SERIAL   adb serial, when more than one device is attached
#   -o DIR      where to write (default: devices/galaxy-s4/soc-dump/, which git ignores)
#   env ADB     the adb binary (default: adb)
#
# Read-only: it runs cat, ls and getprop on the phone and nothing else. It asks for a short list of
# properties rather than the whole of getprop, and it blanks serial numbers, IMEIs and MAC addresses
# out of what it saves, so a dump can be attached to an issue. Nothing is flashed, rooted or unlocked.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ADB=${ADB:-adb}
SERIAL=
OUTBASE=$HERE/soc-dump

die() { echo "pull-soc.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
	case "$1" in
	-s) [ $# -ge 2 ] || die "-s needs a serial"; SERIAL=$2; shift 2 ;;
	-o) [ $# -ge 2 ] || die "-o needs a directory"; OUTBASE=$2; shift 2 ;;
	-h|--help) sed -n '3,/^set -u/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;;
	*) die "unknown argument: $1 (try --help)" ;;
	esac
done

adbc() { "$ADB" ${SERIAL:+-s "$SERIAL"} "$@"; }
# run a command on the phone; old Androids answer with CRLF; blank anything that identifies the owner
phone() {
	adbc shell "$1" 2>/dev/null | tr -d '\r' |
		sed -E -e 's/(serialno=|serial=|imei=|imei[0-9]*=|macaddr=|mac=|bt_addr=|wifi_addr=)[^ ]*/\1<blanked>/g' \
		       -e 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/xx:xx:xx:xx:xx:xx/g' \
		       -e '/^Serial[[:space:]]*:/d'
}

adbc get-state >/dev/null 2>&1 || die "no phone on adb (USB debugging on? try: $ADB devices)"

model=$(phone 'getprop ro.product.model' | head -n1)
stamp=$(date -u +%Y%m%d-%H%M%S)
dir=$OUTBASE/$(echo "${model:-s4}" | tr -c 'A-Za-z0-9\n' '_')-$stamp
mkdir -p "$dir" || die "cannot create $dir"

# a short list of properties, none of which names the owner or the unit
{
	for p in ro.product.model ro.product.device ro.product.name ro.product.manufacturer ro.board.platform \
	         ro.hardware ro.bootloader ro.baseband ro.build.version.release ro.build.version.sdk \
	         ro.build.fingerprint ro.boot.warranty_bit ro.warranty_bit ro.boot.em.status ro.chipname; do
		printf '%s=%s\n' "$p" "$(phone "getprop $p" | head -n1)"
	done
} > "$dir/props.txt"

phone 'cat /proc/cpuinfo' > "$dir/cpuinfo.txt"
phone 'cat /proc/iomem' > "$dir/iomem.txt"
phone 'cat /proc/interrupts' > "$dir/interrupts.txt"
phone 'cat /proc/meminfo' > "$dir/meminfo.txt"
phone 'cat /proc/cmdline' > "$dir/cmdline.txt"
phone 'cat /proc/version' > "$dir/version.txt"
phone 'cat /proc/partitions' > "$dir/partitions.txt"
phone 'ls -l /dev/block/platform/*/by-name/ 2>/dev/null' > "$dir/by-name.txt"
phone 'for f in name virtual_size bits_per_pixel stride modes; do echo "$f: $(cat /sys/class/graphics/fb0/$f 2>/dev/null)"; done' > "$dir/fb0.txt"
phone 'for f in possible present online; do echo "$f: $(cat /sys/devices/system/cpu/$f 2>/dev/null)"; done; echo "cpu0 max_khz: $(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)"' > "$dir/cpu-sysfs.txt"

# --- what it says ------------------------------------------------------------------------------
field() { grep -m1 -i "^$1" "$dir/cpuinfo.txt" | sed 's/^[^:]*:[[:space:]]*//'; }
prop()  { sed -n "s/^$1=//p" "$dir/props.txt" | head -n1; }
hexs()  { printf '0x%08x' "$1" 2>/dev/null || echo "?"; }

imp=$(field 'CPU implementer'); var=$(field 'CPU variant'); part=$(field 'CPU part'); rev=$(field 'CPU revision')
feat=$(field 'Features')
ncpu=$(grep -c '^processor' "$dir/cpuinfo.txt")
midr="?"
if [ -n "$imp" ] && [ -n "$var" ] && [ -n "$part" ] && [ -n "$rev" ]; then
	midr=$(hexs $(( (imp << 24) | (var << 20) | (0xF << 16) | (part << 4) | rev )))
fi

# armv7s -- what an A6 iPhone (5, 5c) runs, and so what the iOS 10.3 images for them contain -- needs
# these. LLVM's models of both Swift (armv7s) and Krait have all of them.
need="neon vfpv3 vfpv4 idiva idivt"
missing=
for f in $need; do case " $feat " in *" $f "*) ;; *) missing="$missing $f" ;; esac; done

{
	echo "Galaxy S4 survey -- $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo
	echo "phone     : $(prop ro.product.manufacturer) $(prop ro.product.model) ($(prop ro.product.device)), Android $(prop ro.build.version.release), bootloader $(prop ro.bootloader)"
	echo "platform  : ro.board.platform=$(prop ro.board.platform) ro.hardware=$(prop ro.hardware)"
	echo "Knox bit  : ro.boot.warranty_bit=$(prop ro.boot.warranty_bit) ro.warranty_bit=$(prop ro.warranty_bit)  (1 = already tripped; blank = property not present)"
	echo
	echo "CPU       : $ncpu cores, implementer ${imp:-?} variant ${var:-?} part ${part:-?} revision ${rev:-?}  -> MIDR $midr"
	echo "features  : ${feat:-?}"
	if [ -z "$feat" ]; then
		echo "armv7s    : UNKNOWN (no Features line in cpuinfo)"
	elif [ -z "$missing" ]; then
		echo "armv7s    : yes -- has $need, so code built for the A6 should run (the loader is what has to be written)"
	else
		echo "armv7s    : NO -- missing:$missing. The A6 images (armv7s) would not run on this CPU."
	fi
	echo "timers    : which timers Android's kernel has interrupts for (an arch_timer line would mean the ARM"
	echo "            architected timer exists; the mainline device tree describes only Qualcomm's own):"
	grep -iE 'timer' "$dir/interrupts.txt" | sed 's/^/            /'
	echo "            (to be sure, read ID_PFR1 bits 19:16 from a bare-metal test: 0 = no generic timer)"
	echo
	echo "memory    : $(sed -n 's/^MemTotal:[[:space:]]*//p' "$dir/meminfo.txt" | head -n1) usable by Android; physical ranges:"
	grep -i 'System RAM' "$dir/iomem.txt" | sed 's/^/            /'
	echo "            (apq8064.h assumes the first range starts at S4_RAM_BASE 0x80000000)"
	echo
	echo "display   : fb0 $(grep -m1 '^name:' "$dir/fb0.txt" | sed 's/^name: *//')  virtual_size $(grep -m1 '^virtual_size:' "$dir/fb0.txt" | sed 's/^virtual_size: *//')  bpp $(grep -m1 '^bits_per_pixel:' "$dir/fb0.txt" | sed 's/^bits_per_pixel: *//')  stride $(grep -m1 '^stride:' "$dir/fb0.txt" | sed 's/^stride: *//')"
	echo "            framebuffer-looking ranges in iomem (the physical address is not in sysfs):"
	grep -iE 'fb|mdp|framebuffer' "$dir/iomem.txt" | sed 's/^/            /'
	echo
	echo "partitions (by-name -> device -> size); the ones the port cares about:"
	# join by-name.txt ("... NAME -> /dev/block/mmcblk0pN") with partitions.txt ("major minor 1K-blocks name")
	awk 'NR==FNR { if ($4 != "") blocks[$4] = $3; next }
	     { for (i = 1; i <= NF; i++) if ($i == "->") { n = $(i-1); d = $(i+1); sub(".*/", "", d);
	       printf "%-12s %-14s %8.1f MiB\n", n, d, (blocks[d] + 0) / 1024 } }' \
		"$dir/partitions.txt" "$dir/by-name.txt" > "$dir/partitions-by-name.txt"
	grep -iE '^(BOOT|RECOVERY|ABOOT|SBL[0-9]|MODEM|SYSTEM|USERDATA|CACHE|HIDDEN|PERSDATA|EFS|PARAM)[[:space:]]' "$dir/partitions-by-name.txt" | sed 's/^/            /'
	[ -s "$dir/partitions-by-name.txt" ] || echo "            (no /dev/block/platform/*/by-name on this phone: see partitions.txt)"
	echo "            all of them: partitions-by-name.txt"
	echo
	echo "files in $dir: props cpuinfo iomem interrupts meminfo cmdline version partitions by-name fb0 cpu-sysfs"
} > "$dir/summary.txt"

cat "$dir/summary.txt"
echo
echo "pull-soc.sh: written to $dir"
