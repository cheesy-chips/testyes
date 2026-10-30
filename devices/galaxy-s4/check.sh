#!/bin/bash
# SPDX-License-Identifier: MIT
# Self-test of the Galaxy S4 scaffold. It needs no phone, no network and nothing of Apple's or Samsung's,
# and takes a few seconds. `make s4-check` runs it, and so does ci/github-check.yml.
#
# What it checks:
#   - the scripts parse, the Python tool compiles, and this directory holds text only (no firmware,
#     no image: the rule of the repository)
#   - apq8064.h compiles for a 32-bit ARM target and the numbers derived in it agree with each other
#   - the claim that the armv7s choice rests on: clang's models of Krait and of Swift (the A6 of the
#     iPhone 5 and 5c) have the same VFPv4, NEON and hardware-divide features, and the A5's Cortex-A9
#     has neither VFPv4 nor divide
#   - mkbootimg.sh writes the header the S4's bootloader reads, and refuses an image that would not
#     fit the BOOT partition
#   - pull-soc.sh, run against a synthetic adb (not a phone), computes the right MIDR, reaches the
#     right armv7s verdict and keeps serial numbers, IMEIs and MAC addresses out of what it writes
#   - tools/xnu-port-check.py, tools/xnu-arm32-survey.sh and tools/xnu-abi-diff.py classify a miniature
#     XNU the way they say
#   - the README of this directory names every file in it, and the paths that it and
#     docs/s4-armv7-port.md point to exist
#
# This cannot show that anything boots. It shows that the tools measure what they say they measure.
#
# usage: devices/galaxy-s4/check.sh      exit status 0 when every check passed; a check that cannot run
#                                        here (no clang, no git) is printed as "skip" and does not fail
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TOP=$(cd "$HERE/../.." && pwd)

case "${1:-}" in -h|--help) sed -n '3,/^set -u/p' "$0" | sed -e '$d' -e 's/^# \{0,1\}//'; exit 0 ;; esac

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0 skipped=0

ok()      { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()     { fail=$((fail + 1)); printf '  FAIL  %s\n' "$1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | head -n 12 | sed 's/^/          /'; }
skip()    { skipped=$((skipped + 1)); printf '  skip  %s (%s)\n' "$1" "$2"; }
section() { printf '\n%s\n' "$1"; }
# check NAME CMD...: ok when CMD succeeds; FAIL, with what it printed, when it does not
check()   { local name=$1 out; shift; if out=$("$@" 2>&1); then ok "$name"; else bad "$name" "$out"; fi; }
# expect NAME GOT WANT: ok when the two are equal
expect()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "got:  $2
want: $3"; fi; }
have()    { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------------------------------
section "files"
for f in "$HERE"/*.sh "$TOP/tools/xnu-arm32-survey.sh"; do
	check "bash -n ${f#"$TOP"/}" bash -n "$f"
	[ -x "$f" ] && ok "${f#"$TOP"/} is executable" || bad "${f#"$TOP"/} is not executable (chmod +x)"
done
if have python3; then
	for t in xnu-port-check xnu-abi-diff; do
		check "tools/$t.py compiles" python3 -I -c 'import sys; compile(open(sys.argv[1]).read(), sys.argv[1], "exec")' "$TOP/tools/$t.py"
		[ -x "$TOP/tools/$t.py" ] && ok "tools/$t.py is executable" || bad "tools/$t.py is not executable (chmod +x)"
	done
else
	skip "tools/xnu-port-check.py compiles" "no python3"
fi
# a survey of someone's phone goes to soc-dump/, which git ignores; everything else here is text
nontext=$(cd "$HERE" && find . -type f -not -path './soc-dump/*' -print0 |
	while IFS= read -r -d '' f; do tr -d '\000' < "$f" | cmp -s - "$f" || echo "$f"; done)
[ -z "$nontext" ] && ok "devices/galaxy-s4 holds text only" || bad "devices/galaxy-s4 holds a file that is not text" "$nontext"

# ---------------------------------------------------------------------------------------------------
section "apq8064.h"
arm_clang=0
if have clang && clang --target=armv7-none-eabi -mcpu=krait -fsyntax-only -x c /dev/null >/dev/null 2>&1; then
	arm_clang=1
	cat > "$tmp/hdr.c" <<'EOF'
#include "apq8064.h"
_Static_assert(sizeof(unsigned int) == 4, "the S4 is a 32-bit machine");
_Static_assert(S4_BOOT_BASE + S4_BOOT_KERNEL_OFFSET == 0x80208000u, "kernel address");
_Static_assert(S4_BOOT_KERNEL_ADDR == 0x80208000u, "kernel address, derived");
_Static_assert(S4_BOOT_RAMDISK_ADDR == 0x82200000u, "ramdisk address");
_Static_assert(S4_BOOT_TAGS_ADDR == 0x80200100u, "tags address");
_Static_assert(S4_BOOT_PARTITION_MAX == 10u * 1024u * 1024u, "the BOOT partition is 10 MiB");
_Static_assert(APQ8064_QGIC_CPU_BASE == APQ8064_QGIC_DIST_BASE + 0x2000u, "the QGIC's two blocks are 8 KiB apart");
_Static_assert(APQ8064_SPI(158) == 190u && APQ8064_PPI(2) == 18u, "GIC interrupt numbering");
_Static_assert(APQ8064_KPSS_GPT0_IRQ == APQ8064_KPSS_TIMER_IRQ_FIRST + 1u, "GPT0 is the second of the timer's interrupts");
_Static_assert(APQ8064_KPSS_DGT_HZ == 6750000u, "27 MHz divided by 4");
_Static_assert(APQ8064_KPSS_STS_OFFSET < APQ8064_KPSS_TIMER_SIZE, "the status register is inside the timer's window");
_Static_assert(APQ8064_KPSS_DGT_OFFSET + APQ8064_KPSS_DGT_CLK_CTL + 4u <= APQ8064_KPSS_TIMER_SIZE, "so is the DGT's clock control");
_Static_assert(APQ8064_ACC0_BASE + 3u * APQ8064_ACC_STRIDE == 0x020b8000u, "acc3 as in the device tree");
_Static_assert(APQ8064_SAW0_BASE + 3u * APQ8064_SAW_STRIDE == 0x020b9000u, "saw3 as in the device tree");
_Static_assert(S4_RAMOOPS_BASE >= S4_RAM_BASE, "ramoops is in RAM");
_Static_assert(S4_CONSOLE_BAUD == 115200u, "console speed");
int main_is_not_needed;
EOF
	check "compiles for armv7 (-mcpu=krait) and its derived numbers agree" \
		clang --target=armv7-none-eabi -mcpu=krait -nostdinc -std=c11 -pedantic -Wall -Wextra -Werror \
		      -fsyntax-only -I "$HERE" -x c "$tmp/hdr.c"
else
	skip "apq8064.h compiles for armv7" "no clang with an ARM target"
fi

# ---------------------------------------------------------------------------------------------------
section "the armv7s choice (docs/s4-armv7-port.md)"
if [ "$arm_clang" = 1 ]; then
	feats() { clang --target=armv7-none-eabi -mcpu="$1" -mfloat-abi=hard -### -c -x c /dev/null 2>&1 | tr ' ' '\n' | tr -d '"' | grep -E '^[+]' | tr '\n' ' '; }
	for cpu in krait swift; do
		f=" $(feats "$cpu")"
		missing=
		for need in +neon +vfp4 +hwdiv +hwdiv-arm; do case "$f" in *" $need "*) ;; *) missing="$missing $need" ;; esac; done
		[ -z "$missing" ] && ok "clang's $cpu has neon, vfpv4 and divide in ARM and Thumb state" || bad "clang's $cpu lacks:$missing"
	done
	f=" $(feats cortex-a9)"
	case "$f" in
	*" +vfp4 "*|*" +hwdiv "*) bad "clang's cortex-a9 (the A5) should have neither vfpv4 nor hardware divide" ;;
	*) ok "clang's cortex-a9 (the A5) has neither vfpv4 nor hardware divide" ;;
	esac
	printf 'int d(int a, int b) { return a / b; }\n' > "$tmp/div.c"
	for cpu in krait swift; do
		if clang --target=armv7-none-eabi -mcpu="$cpu" -O2 -S -o - "$tmp/div.c" 2>/dev/null | grep -qE '(^|[[:space:]])sdiv[[:space:]]'; then
			ok "code built for $cpu divides with sdiv"
		else
			bad "code built for $cpu does not use sdiv"
		fi
	done
else
	skip "krait, swift and cortex-a9 feature sets" "no clang with an ARM target"
fi

# ---------------------------------------------------------------------------------------------------
section "mkbootimg.sh"
if have python3; then
	head -c 4096 /dev/zero > "$tmp/k.bin"            # stand-ins: zeros and noise, nothing real
	head -c 3000 /dev/urandom > "$tmp/r.bin"
	if "$HERE/mkbootimg.sh" -o "$tmp/ok.img" --kernel "$tmp/k.bin" --ramdisk "$tmp/r.bin" \
	                        --cmdline "console=ttyHSL0,115200" > "$tmp/mk.log" 2>&1; then
		got=$(python3 -I - "$tmp/ok.img" <<'EOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
magic, ksz, kaddr, rsz, raddr, ssz, saddr, taddr, page, hv = struct.unpack_from('<8s9I', d, 0)
print(magic.decode(), hex(kaddr), hex(raddr), hex(taddr), page, ksz, rsz,
      d[48:64].rstrip(b'\0').decode(), d[64:576].rstrip(b'\0').decode())
EOF
)
		expect "header: magic, kernel/ramdisk/tags addresses, page, sizes, board, cmdline" "$got" \
		       "ANDROID! 0x80208000 0x82200000 0x80200100 2048 4096 3000 jflte console=ttyHSL0,115200"
	else
		bad "mkbootimg.sh failed on a small kernel and ramdisk" "$(cat "$tmp/mk.log")"
	fi
	head -c $((10 * 1024 * 1024)) /dev/zero > "$tmp/big.bin"
	if "$HERE/mkbootimg.sh" -o "$tmp/big.img" --kernel "$tmp/big.bin" > "$tmp/big.log" 2>&1; then
		bad "an image over the 10 MiB of the BOOT partition should be refused"
	elif [ -e "$tmp/big.img" ]; then
		bad "the refused image should not be left behind"
	else
		ok "refuses an image over the BOOT partition and leaves no file"
	fi
else
	skip "mkbootimg.sh" "no python3"
fi

# ---------------------------------------------------------------------------------------------------
section "pull-soc.sh against a synthetic adb (not a phone)"
mkdir "$tmp/fake"
cat > "$tmp/fake/adb" <<'EOF'
#!/bin/bash
# SYNTHETIC stand-in for adb, used only to exercise pull-soc.sh. None of this is output from a real phone.
[ "$1" = "-s" ] && shift 2
case "$1" in
get-state) echo device; exit 0 ;;
shell) ;;
*) exit 1 ;;
esac
cmd=$2
FEAT=${FAKE_FEATURES:-"swp half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt"}
case "$cmd" in
"getprop ro.product.model") printf 'GT-I9505\r\n' ;;
"getprop ro.product.device") printf 'jflte\r\n' ;;
"getprop ro.product.name") printf 'jfltexx\r\n' ;;
"getprop ro.product.manufacturer") printf 'samsung\r\n' ;;
"getprop ro.board.platform") printf 'msm8960\r\n' ;;
"getprop ro.hardware") printf 'qcom\r\n' ;;
"getprop ro.bootloader") printf 'I9505XXSYNTH1\r\n' ;;
"getprop ro.build.version.release") printf '5.0.1\r\n' ;;
"getprop ro.boot.warranty_bit") printf '0\r\n' ;;
"getprop "*) printf '\r\n' ;;
"cat /proc/cpuinfo")
  for i in 0 1 2 3; do
    printf 'processor\t: %s\nBogoMIPS\t: 13.52\nFeatures\t: %s\nCPU implementer\t: 0x51\nCPU architecture: 7\nCPU variant\t: 0x1\nCPU part\t: 0x06f\nCPU revision\t: 0\n\n' "$i" "$FEAT"
  done
  printf 'Hardware\t: SYNTH\nSerial\t\t: 00000000deadbeef\n' ;;
"cat /proc/iomem") printf '80000000-8fffffff : System RAM\n  80208000-80f00000 : Kernel code\n90000000-9fffffff : System RAM\n  a0000000-a0ffffff : msm_fb\n' ;;
"cat /proc/interrupts") printf '  16: 100 GIC timer\n' ;;
"cat /proc/meminfo") printf 'MemTotal:        1950000 kB\nMemFree: 1 kB\n' ;;
"cat /proc/cmdline") printf 'console=null androidboot.hardware=qcom androidboot.serialno=SYNTHSERIAL123 androidboot.imei=123456789012345 wifi_addr=aa:bb:cc:dd:ee:ff btaddr=11:22:33:44:55:66\n' ;;
"cat /proc/version") printf 'Linux version 3.4.0-synthetic\n' ;;
"cat /proc/partitions") printf 'major minor  #blocks  name\n\n 179        0   15267840 mmcblk0\n 179       20      10240 mmcblk0p20\n 179       21      10240 mmcblk0p21\n 179       23    2097152 mmcblk0p23\n' ;;
"ls -l /dev/block/platform/"*) printf 'lrwxrwxrwx root     root              2014-01-01 00:00 BOOT -> /dev/block/mmcblk0p20\nlrwxrwxrwx root     root              2014-01-01 00:00 RECOVERY -> /dev/block/mmcblk0p21\nlrwxrwxrwx root     root              2014-01-01 00:00 SYSTEM -> /dev/block/mmcblk0p23\n' ;;
*"fb0"*) printf 'name: msmfb42_90501\nvirtual_size: 1080,3840\nbits_per_pixel: 32\nstride: 4320\nmodes: U:1080x1920p-0\n' ;;
*"cpu/possible"*|*"cpu/\$f"*) printf 'possible: 0-3\npresent: 0-3\nonline: 0-3\ncpu0 max_khz: 1890000\n' ;;
*) : ;;
esac
EOF
chmod +x "$tmp/fake/adb"

if ADB="$tmp/fake/adb" "$HERE/pull-soc.sh" -o "$tmp/soc" > "$tmp/soc.log" 2>&1; then
	sum=$(cat "$tmp"/soc/*/summary.txt)
	case "$sum" in *"MIDR 0x511f06f0"*) ok "MIDR from implementer 0x51, variant 0x1, part 0x06f, revision 0 is 0x511f06f0" ;;
	               *) bad "MIDR is not 0x511f06f0" "$(printf '%s\n' "$sum" | grep '^CPU')" ;; esac
	case "$sum" in *"armv7s    : yes"*) ok "armv7s verdict is yes with neon vfpv3 vfpv4 idiva idivt" ;;
	               *) bad "armv7s verdict should be yes" "$(printf '%s\n' "$sum" | grep '^armv7s')" ;; esac
	printf '%s\n' "$sum" | grep -Eq 'BOOT +mmcblk0p20 +10\.0 MiB' && ok "BOOT partition joined to its size: 10.0 MiB" || bad "BOOT partition line is missing or wrong" "$(printf '%s\n' "$sum" | grep -i boot)"
	leaks=$(grep -rE 'SYNTHSERIAL123|123456789012345|aa:bb:cc:dd:ee:ff|11:22:33:44:55:66|deadbeef' "$tmp/soc" || true)
	[ -z "$leaks" ] && ok "no serial number, IMEI or MAC address in anything it wrote" || bad "an identifier was written to disk" "$leaks"
else
	bad "pull-soc.sh failed against the synthetic adb" "$(cat "$tmp/soc.log")"
fi
if FAKE_FEATURES="swp half thumb fastmult vfp edsp neon vfpv3 tls" ADB="$tmp/fake/adb" "$HERE/pull-soc.sh" -o "$tmp/soc2" > "$tmp/soc2.log" 2>&1; then
	case "$(cat "$tmp"/soc2/*/summary.txt)" in
	*"armv7s    : NO -- missing: vfpv4 idiva idivt"*) ok "a CPU without vfpv4 and divide gets armv7s verdict NO" ;;
	*) bad "the armv7s verdict should be NO for a CPU without vfpv4, idiva, idivt" "$(grep armv7s "$tmp"/soc2/*/summary.txt)" ;;
	esac
else
	bad "pull-soc.sh failed on the second synthetic phone" "$(cat "$tmp/soc2.log")"
fi
out=$(ADB="$tmp/fake/no-such-adb" "$HERE/pull-soc.sh" -o "$tmp/soc3" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && case "$out" in *"no phone on adb"*) true ;; *) false ;; esac; then
	ok "no phone: says so and exits non-zero"
else
	bad "no phone should give an error naming adb (exit $rc)" "$out"
fi

# ---------------------------------------------------------------------------------------------------
section "tools/xnu-port-check.py and tools/xnu-arm32-survey.sh on a miniature XNU"
if have git && have patch && have python3; then
	g="git -c user.name=check -c user.email=check@invalid -c init.defaultBranch=main -c commit.gpgsign=false"
	w=$tmp/pc
	mkdir -p "$w/src/osfmk" "$w/tree/osfmk" "$w/files/osfmk" "$w/files/bsd/dev"
	for n in a b c; do seq 1 20 | sed 's/^/line /' > "$w/src/osfmk/$n.c"; done
	seq 1 40 | sed 's/^/line /' > "$w/src/osfmk/p.c"
	seq 1 20 | sed 's/^/line /' > "$w/src/osfmk/f.c"
	(
		cd "$w/src" && git init -q && git add -A && $g commit -q -m v1 &&
		for n in a b c; do sed -i.bak 's/^line 10$/line ten, changed/' "osfmk/$n.c" && rm -f "osfmk/$n.c.bak"; done &&
		sed -i.bak 's/^line 5$/line five, changed/; s/^line 35$/line 35, changed/' osfmk/p.c && rm -f osfmk/p.c.bak &&
		sed -i.bak 's/^line 10$/line ten, changed/' osfmk/f.c && rm -f osfmk/f.c.bak &&
		seq 1 3 | sed 's/^/new /' > osfmk/d.c && seq 1 3 | sed 's/^/new /' > osfmk/e.c &&
		git add -A && git diff --cached > "$w/test.patch"
	) >/dev/null 2>&1
	# the release being tested: a.c as it was (fits), f.c with the outermost context line of the change
	# altered (fits with fuzz), p.c with one of its two hunks gone stale, b.c rewritten around the change
	# (fails), no c.c (missing), no d.c (a new file that fits), e.c already there (a new file that collides)
	seq 1 20 | sed 's/^/line /' > "$w/tree/osfmk/a.c"
	seq 1 20 | sed 's/^/other /' > "$w/tree/osfmk/b.c"
	seq 1 20 | sed 's/^/line /; s/^line 7$/line seven/' > "$w/tree/osfmk/f.c"
	seq 1 40 | sed 's/^/line /; s/^line 3[0-9]$/other/' > "$w/tree/osfmk/p.c"   # p.c: first hunk fits, second does not
	printf 'old\n' > "$w/tree/osfmk/e.c"
	printf 'x\n' > "$w/files/osfmk/a.c"; printf 'x\n' > "$w/files/bsd/dev/hakios.t.c"
	out=$(python3 -I "$TOP/tools/xnu-port-check.py" "$w/tree" --patch "$w/test.patch" --files "$w/files" --list 2>&1)
	line() { printf '%s\n' "$out" | grep -E "$1" | tr -s ' ' | sed 's/^ //'; }
	expect "one file applies cleanly"                    "$(line 'apply cleanly')"                 "apply cleanly (exact or shifted lines) 1"
	expect "one file applies only with fuzz"             "$(line 'apply with fuzz')"               "apply with fuzz (check by hand) 1"
	expect "one new file fits"                           "$(line 'new files that fit')"            "new files that fit 1"
	expect "one file has a hunk that fits and one that does not" "$(line 'some hunks fail')"       "some hunks fail 1"
	expect "one file fails every hunk"                   "$(line 'every hunk fails')"              "every hunk fails 1"
	expect "one file is not in that release"             "$(line 'not in that release')"           "file is not in that release 1"
	expect "one new file collides with an existing path" "$(line 'new file, but the path exists')" "new file, but the path exists there 1"
	expect "the total"                                   "$(line '^  =>')"                         "=> 3 of 7 files go in (42%); hunks that fail: 2 of 5"
	case "$out" in *"missing      osfmk/c.c"*) ok "--list names the missing file" ;; *) bad "--list should name osfmk/c.c as missing" "$out" ;; esac
	case "$out" in *"paths that already exist in this release (would be overwritten): 1"*) ok "xnu/files that would overwrite a file of the release are counted" ;; *) bad "the overwrite count should be 1" "$out" ;; esac

	x=$tmp/xnu
	mkdir -p "$x/osfmk/arm" "$x/makedefs" "$x/pexpert/pexpert/arm"
	: > "$x/osfmk/arm/locore.s"
	printf 'SUPPORTED_ARM_MACHINE_CONFIGS = T8002 T8004\nSUPPORTED_ARM64_MACHINE_CONFIGS = BCM2837\n' > "$x/makedefs/MakeInc.def"
	printf 'a\nb\n' > "$x/pexpert/pexpert/arm/board_config.h"
	( cd "$x" && git init -q && git add -A && $g commit -q -m t && git tag xnu-test &&
	  git rm -q osfmk/arm/locore.s && sed -i.bak 's/= T8002 T8004/= NONE/' makedefs/MakeInc.def && rm -f makedefs/MakeInc.def.bak &&
	  git add -A && $g commit -q -m t2 && git tag xnu-test2 ) >/dev/null 2>&1
	rows=$(XNU_URL="file://$x" "$TOP/tools/xnu-arm32-survey.sh" xnu-test xnu-test2 2>&1 | grep '^xnu-test' | tr -s ' ')
	expect "survey, a release with 32-bit code: files, osfmk/arm, osfmk/arm64, locore.s, both config lists, board_config.h lines" \
	       "$(printf '%s\n' "$rows" | grep '^xnu-test ')" "xnu-test 3 1 0 yes T8002 T8004 BCM2837 2"
	expect "survey, a release without it (locore.s gone, no 32-bit machine)" \
	       "$(printf '%s\n' "$rows" | grep '^xnu-test2 ')" "xnu-test2 2 0 0 no NONE BCM2837 2"
	"$TOP/tools/xnu-arm32-survey.sh" --help 2>&1 | grep -q 'usage: tools/xnu-arm32-survey.sh' && ok "survey --help prints its usage" || bad "survey --help does not print its usage"
else
	skip "xnu-port-check.py / xnu-arm32-survey.sh" "needs git, patch and python3"
fi

# ---------------------------------------------------------------------------------------------------
section "tools/xnu-abi-diff.py on two miniature kernels"
if have python3; then
	a=$tmp/abi
	mkdir -p "$a/old/bsd/kern" "$a/old/osfmk/mach" "$a/new/bsd/kern" "$a/new/osfmk/mach"
	cat > "$a/old/bsd/kern/syscalls.master" <<'EOF'
0	AUE_NULL	ALL	{ int nosys(void); }   { indirect syscall }
1	AUE_EXIT	ALL	{ void exit(int rval) NO_SYSCALL_STUB; }
2	AUE_FORK	ALL	{ int fork(void) NO_SYSCALL_STUB; }
3	AUE_NULL	ALL	{ user_ssize_t read(int fd, user_addr_t cbuf, user_size_t nbyte); }
4	AUE_NULL	ALL	{ user_ssize_t write(int fd, user_addr_t cbuf, user_size_t nbyte); }
5	AUE_NULL	ALL	{ int watchevent(proc_t p, struct watchevent_args *uap); }
6	AUE_VFORK	ALL	{ int vfork(void); }
7	AUE_NULL	ALL	{ int oldname(int a); }
8	AUE_NULL	ALL	{ int moved(int a); }
10	AUE_NULL	ALL	{ int enosys(void); }
11	AUE_CLOSE	ALL	{ int close(int fd); }
EOF
	cat > "$a/new/bsd/kern/syscalls.master" <<'EOF'
0	AUE_NULL	ALL	{ int nosys(void); }   { indirect syscall }
1	AUE_EXIT	ALL	{ void exit(int rval) NO_SYSCALL_STUB; }
2	AUE_FORK	ALL	{ int fork(void) NO_SYSCALL_STUB; }
3	AUE_NULL	ALL	{ user_ssize_t read(int fd, user_addr_t cbuf, user_size_t nbyte, int flags); }
4	AUE_NULL	ALL	{ user_ssize_t write(int fildes, user_addr_t buffer, user_size_t count); }
5	AUE_NULL	ALL	{ int nosys(void); }   { old watchevent }
#if CONFIG_VFORK
6	AUE_VFORK	ALL	{ int vfork(void) NO_SYSCALL_STUB; }
#else
6	AUE_NULL	ALL	{ int nosys(void); }   { old vfork }
#endif
7	AUE_NULL	ALL	{ int renamed_call(int a); }
9	AUE_NULL	ALL	{ int moved(int a); }
10	AUE_NULL	ALL	{ int enosys(void); }
11	AUE_CLOSE	ALL	{ int sys_close(int fd); }
EOF
	cat > "$a/old/osfmk/mach/syscall_sw.h" <<'EOF'
#ifdef	PRIVATE
#ifndef	_MACH_SYSCALL_SW_H_
#define _MACH_SYSCALL_SW_H_
kernel_trap(_kernelrpc_mach_vm_allocate_trap,-10,5)
kernel_trap(_kernelrpc_mach_port_destroy_trap,-17,2)
#if defined(__LP64__)
kernel_trap(mach_wait_until,-90,1)
#else	/* __LP64__ */
kernel_trap(mach_wait_until,-90,2)
#endif	/* __LP64__ */
#endif	/* _MACH_SYSCALL_SW_H_ */
#endif	/* PRIVATE */
EOF
	cat > "$a/new/osfmk/mach/syscall_sw.h" <<'EOF'
#ifdef	PRIVATE
#ifndef	_MACH_SYSCALL_SW_H_
#define _MACH_SYSCALL_SW_H_
kernel_trap(_kernelrpc_mach_vm_allocate_trap,-10,5)
#if defined(__LP64__)
kernel_trap(mach_wait_until,-90,1)
#else	/* __LP64__ */
kernel_trap(mach_wait_until,-90,3)
#endif	/* __LP64__ */
#endif	/* _MACH_SYSCALL_SW_H_ */
#endif	/* PRIVATE */
EOF
	# MIG: foo loses a routine (it becomes a skip, the ids stay), foo2 swaps its two, stale.defs is not built by either
	printf 'MIG_DEFS = \\\n\tfoo.defs \\\n\tfoo2.defs\n' > "$a/old/osfmk/mach/Makefile"
	cp "$a/old/osfmk/mach/Makefile" "$a/new/osfmk/mach/Makefile"
	printf 'subsystem foo 100;\nroutine alpha(a : int);\nroutine beta(a : int; b : int);\nroutine gamma(a : int);\n' > "$a/old/osfmk/mach/foo.defs"
	printf 'subsystem foo 100;\nroutine alpha(a : int);\nskip;\nroutine gamma(a : int);\n' > "$a/new/osfmk/mach/foo.defs"
	printf 'subsystem foo2 200;\nroutine one();\nroutine two();\n' > "$a/old/osfmk/mach/foo2.defs"
	printf 'subsystem foo2 200;\nroutine two();\nroutine one();\n' > "$a/new/osfmk/mach/foo2.defs"
	printf 'subsystem stale 900;\nroutine s1(a : int);\n' > "$a/old/osfmk/mach/stale.defs"

	abi() { python3 -I "$TOP/tools/xnu-abi-diff.py" "$a/old" "$a/new" "$@" 2>&1; }
	para() { awk -v RS= -v ORS='\n' "NR==$1" | tr -s ' '; }       # the Nth paragraph, runs of spaces squeezed
	quiet=$(abi --quiet)
	expect "BSD system calls: same (also with other parameter names, sys_ prefix, enosys slots ignored), arguments differ, moved, renamed, gone, and one that went behind an #if" \
	       "$(printf '%s\n' "$quiet" | para 2)" "BSD system calls: 9 in OLD, 8 in NEW; of OLD's:
 5 same number, same name, same arguments
 1 same number and name, arguments differ
 1 same name at another number
 1 number now means a different call
 1 gone from NEW
 1 (of the first two groups: built in NEW only behind an #if that OLD did not have)"
	expect "Mach traps, 32-bit variants: one argument count changed, one trap gone" \
	       "$(printf '%s\n' "$quiet" | para 3)" "Mach traps (32-bit): 3 in OLD, 2 in NEW; of OLD's:
 1 same number, same name, same arguments
 1 same number and name, arguments differ
 0 same name at another number
 0 number now means a different call
 1 gone from NEW
 0 (of the first two groups: built in NEW only behind an #if that OLD did not have)"
	expect "Mach traps, --lp64: the 64-bit variant did not change" \
	       "$(abi --quiet --lp64 | para 3 | sed -n '1,2p;6p')" "Mach traps (64-bit): 3 in OLD, 2 in NEW; of OLD's:
 2 same number, same name, same arguments
 1 gone from NEW"
	if have clang; then
		expect "MIG: a retired routine keeps its id, a swap is a move, a .defs the Makefile does not list is ignored" \
		       "$(printf '%s\n' "$quiet" | para 4)" "MIG interfaces: 2 subsystems, 5 routines in OLD; of those:
 2 same id, same name
 1 retired: the id is kept, as a skip
 2 same name at another id
 0 id now means a different routine
 0 gone from NEW"
	else
		skip "MIG interfaces" "no clang to preprocess the .defs files"
	fi
	full=$(abi)
	case "$full" in *"66 vfork"*"only under #if CONFIG_VFORK"*|*" 6 vfork"*"only under #if CONFIG_VFORK"*) ok "the list names vfork as built only under CONFIG_VFORK" ;; *) bad "the list should say that vfork is only under #if CONFIG_VFORK" "$full" ;; esac
	case "$full" in *"kernelrpc_mach_port_destroy_trap"*"gone"*) ok "the list names the trap that is gone" ;; *) bad "the list should name _kernelrpc_mach_port_destroy_trap as gone" "$full" ;; esac
	out=$(python3 -I "$TOP/tools/xnu-abi-diff.py" "$a/old" "$tmp" 2>&1); rc=$?
	if [ "$rc" -ne 0 ] && case "$out" in *"not found"*) true ;; *) false ;; esac; then ok "a directory that is not a kernel tree is refused with a message"; else bad "a directory without syscalls.master should be refused (exit $rc)" "$out"; fi
else
	skip "tools/xnu-abi-diff.py" "no python3"
fi

# ---------------------------------------------------------------------------------------------------
section "documents"
for f in $(cd "$HERE" && ls | grep -v -e '^README.md$' -e '^soc-dump$'); do
	grep -q "$f" "$HERE/README.md" 2>/dev/null && ok "README.md names $f" || bad "README.md does not name $f"
done
for doc in "$HERE/README.md" "$TOP/docs/s4-armv7-port.md"; do
	rel=${doc#"$TOP"/}
	if [ ! -f "$doc" ]; then bad "$rel is missing"; continue; fi
	# paths in `backticks` that point into this repository (code blocks are left alone)
	gone=$(awk '/^```/ { fence = !fence; next } !fence' "$doc" | grep -oE '`[A-Za-z0-9_./-]+`' | tr -d '`' |
		grep -E '^(tools|devices|docs|xnu|xnuloader|sysimage|userland|qemu|ci|wifi)/|^(Makefile|NOTICE|COMPLIANCE\.md|THIRD_PARTY_LICENSES\.md)$' | sort -u |
		while read -r p; do [ -e "$TOP/$p" ] || echo "$p"; done)
	[ -z "$gone" ] && ok "every repository path in $rel exists" || bad "$rel names paths that do not exist" "$gone"
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
