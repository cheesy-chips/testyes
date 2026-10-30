# Galaxy S4: the 32-bit ARM port

Where the port to the Samsung Galaxy S4 stands (October 2026).

**Groundwork only. Nothing of this project has run on an S4, and nothing here boots.** What exists is
what could be done without the phone: measurements of what to build on, a directory for the phone
(`devices/galaxy-s4/`: its SoC constants, a boot-image packer, a read-only survey of a real phone, a
self-test), and three tools that measure how far a given XNU release is from our kernel and from the
iOS it would have to run. A number below is printed by one of those tools, or read from a source named
next to it, or marked **VERIFY**: not established, with a way to establish it.

## What the S4 changes

The request was an S4, with an iOS older than 16.5 allowed. The S4 is a different kind of machine
from the POCO X5 Pro, and the choice of iOS follows from that:

| | POCO X5 Pro 5G (today) | Galaxy S4 (GT-I9505) |
|---|---|---|
| CPU | Snapdragon 778G, 8 cores, 64-bit | Snapdragon 600 (APQ8064T), 4 Krait cores, 32-bit ARMv7 |
| Boot | our UEFI loader through `fastboot boot`; nothing is flashed | Samsung's bootloader: Odin / Download mode, no fastboot; a boot image is flashed |
| Interrupts, timer, cores | GICv3, the ARM generic timer, PSCI | QGIC2 (a GICv2), Qualcomm's KPSS timer, cores started through per-core ACC and SAW blocks |
| RAM | 6 or 8 GB: the whole system image sits in it | about 2 GB (VERIFY): it does not fit |
| Kernel | XNU 8796 (iOS 16.5), 64-bit only | a 32-bit XNU; 8796 has none left |
| User space | iOS 16.5, arm64 | 32-bit iOS: 10.3 is the newest |

"The S4" is taken to be the **GT-I9505** ("jflte"), the Snapdragon 600 model. Its SoC has a device
tree in mainline Linux to read, and its numbers are in `devices/galaxy-s4/apq8064.h`. The GT-I9500 is
another SoC (Exynos 5410, Cortex-A15 and A7) and would need a header of its own. The US carrier models
share the I9505's SoC, but some have locked bootloaders (VERIFY; not covered).

The same SoC family sits in other phones. The Nexus 4 (APQ8064, Google's fastboot bootloader) might let
a first bring-up keep the rule "nothing is flashed" (VERIFY that its bootloader takes `fastboot boot`).
It has not been looked at, and its board (memory map, panel, UART pins) is not the S4's.

## Which iOS

**iOS 10.3.x for the A6 phones** (iPhone 5, 5c, iPad 4: `armv7s` code). The build that was measured is
10.3.3 (14G60) for the iPhone5,3, the iPhone 5c. Not 5, 6 or 7, and not 9, for two reasons.

*They are encrypted.* The project takes the system from Apple's own IPSW "without decrypting or
circumventing anything" (the main README). The key page of each build in the iPhone Wiki lists keys
for every older build that was looked at, which means the files are encrypted; for 10.3.3 it says
"Not Encrypted" against every file:

| iOS | Build | Key page of the build | Usable as it is |
|---|---|---|---|
| 5.1.1 | 9B206 | keys listed | no |
| 6.1.3 | 10B329 | keys listed | no |
| 7.1.2 | 11D257 | keys listed | no |
| 9.3.5 | 13G36 | keys listed for the root filesystem, both ramdisks, the kernelcache, the device tree | no |
| 10.3.3 | 14G60 | "Not Encrypted" for all nine files: the root filesystem, both ramdisks, the kernelcache, the device tree and the boot loaders | yes |

(Each page is for one device of the build; the devices are in the sources at the end.)

*The older the user space, the further it is from a kernel we can build.* Apple published no ARM kernel
before xnu-4570 (next section), so whatever iOS is chosen runs on a kernel newer than itself, and the
gap between the two is the thing to keep small. It was measured for 10.3 (below). It was not measured
for 5, 6 or 7, which cannot be closer.

10.3 is also the last 32-bit iOS (iOS 11 dropped every 32-bit device), so it is the last user space
with a 32-bit code path at all. The A6 phones are the model of what a Krait has to pretend to be, and
the pretence is plausible: LLVM's models of the Krait and of the A6's Swift core have the same VFPv4,
NEON and hardware divide, in ARM and Thumb state, and the A5's Cortex-A9 (the iPhone 4S) has neither
VFPv4 nor divide. `devices/galaxy-s4/check.sh` checks that against the clang it finds, and
`devices/galaxy-s4/pull-soc.sh` checks the real CPU's feature flags on a phone.

What is not known about 10.3, and has to be read from your own IPSW (VERIFY):

- The file system of its root filesystem. iOS 10.3 introduced APFS; one forum post hears that the 32-bit
  devices were not converted and stay on HFS+, and nothing confirms it. We have a read-only APFS driver
  (`bsd/miscfs/apfs/`, written for 64-bit); HFS+ is not in the XNU tree at all (the `hfs` repository of
  apple-oss-distributions has it), so whichever it is, it is work.
- The format of its device tree. It is an IMG3 file (`DeviceTree.n48ap.img3` for the iPhone5,3), not
  the compressed IM4P that `xnuloader/mkidentity.sh` reads for iOS 16.5.
- How its `libsystem_kernel` reads the clock. The commpage has a byte that tells user space whether it
  may read the counter itself (`_COMM_PAGE_USER_TIMEBASE`); what the 10.3 code does with it is in closed
  code, and the published xnu-3789 `libsyscall` has the 32-bit ARM parts removed.
- The size of the expanded root filesystem. The IPSW alone is 1.86 to 1.9 GB (ipsw.me / ipsw.io), the
  expanded system is bigger, and the S4 has about 2 GB. The system cannot live in RAM here the way it
  does on the POCO; it has to be read from storage.

## Which kernel

There is no public ARM XNU before xnu-4570.71.2. Of the last release of each line from OS X 10.5 to
macOS 10.12 (xnu-1228 to xnu-3789, nine releases), none has a file under `osfmk/arm/`, and the kernels
of iOS 5 to 10.3 are in that range. From xnu-4570 the tree carries 32-bit ARM code, and the only 32-bit
machines it defines are Apple Watch SoCs; Apple took the code out again in 8792.
`tools/xnu-arm32-survey.sh` prints the table; the last
column is `tools/xnu-port-check.py` run on a checkout of each release, which asks GNU patch (dry run)
whether the 73 files `xnu/hakios.patch` changes still take their hunks:

| Release | Darwin | `osfmk/arm` files | `locore.s` | 32-bit machine configurations in the build | Patch files that apply (of 73) |
|---|---|---|---|---|---|
| xnu-3789.70.16 | 16 (iOS 10) | 0 | no | none | not tried |
| xnu-4570.71.2 | 17 (iOS 11) | 94 | yes | S7002, T8002, T8004 in `board_config.h` | 10 |
| xnu-6153.141.1 | 19 (iOS 13) | 95 | yes | S7002, T8002, T8004 | 19 |
| xnu-7195.141.2 | 20 (iOS 14) | 101 | yes | T8002, T8004 | 32 |
| **xnu-8020.140.41** | 21 (iOS 15) | 109 | yes | none: the list is `NONE`, `board_config.h` is a 9-line stub | **59** |
| xnu-8792.81.2 | 22 (iOS 16) | 71 | no | none | not tried |
| xnu-8796.121.2 (our base) | 22 (iOS 16.5) | 70 | no | none | 73 (the control) |

**The base is `xnu-8020.140.41`**: the newest release that still has the 32-bit sources
(`locore.s`, the 32-bit start code, pmap, traps): it is the last tag of the 8020 line, and the next
tag Apple published, xnu-8792.41.9, already has none. That also makes it the nearest of the releases
with 32-bit code to the tree our patch is written against. Going back one release more, to 7195, loses another 27 of the 73 files (59 to 32); to 4570,
another 22 (to 10). The price is in the other direction. Apple removed the 32-bit machine definitions
from the build in 8019, so the Krait's has to be written. And 8020 is further than the older releases
from the kernel iOS 10.3 was built for, though not by much (measured below: 10 of the 452 calls and
traps of 3789 differ or are gone in 8020, 2 in 4570); the shims for those 10 are small next to 49 more
patch files that would have to be redone by hand.

The fit is textual. Of the 185 hunks that have a place to go, 18 fail. The 14 files that need work are
`bsd/kern/kern_exec.c`, `bsd/kern/sys_generic.c` and `bsd/vm/vm_unix.c`; the build
(`config/MASTER.arm64.bcm2837`, `makedefs/MakeInc.cmd`, `osfmk/conf/files.arm64`); `osfmk/kern/debug.c`,
`kalloc.h`, `percpu.h` and `work_interval.h`; and four ARM start-up files, two of which are the pmap,
which 8020 keeps at `osfmk/arm/pmap.c` where 8796 has `osfmk/arm/pmap/`. It says nothing about whether
the result builds or boots. Of the 110 files that `xnu/files/` adds, 10 are the 64-bit platform and 53
are drivers for the POCO's hardware; neither carries over.

### The machine configuration to write

The last 32-bit machines in the build were the Apple Watch's T8002 and T8004 (Series 2 and 3), in
xnu-7195. One board class, `T8002`, serves both and is named in 7 files there; 5 of them are still in
8020. The Krait's configuration is made by putting the missing pieces back from 7195 and changing
them:

| Place | What |
|---|---|
| `makedefs/MakeInc.def` | the list of 32-bit machine configurations (`NONE` in 8020) and the `MACHINE_FLAGS_ARM_*` line for each (gone); back from 7195 |
| `makedefs/MakeInc.top` | the default 32-bit configuration, now `NONE` |
| `pexpert/pexpert/arm/board_config.h` | the `ARM_BOARD_CONFIG_*` and `ARM_BOARD_CLASS_*` block; gone, back from 7195 |
| `pexpert/pexpert/arm/` | a new SoC header, next to `T8002.h`, from the numbers in `devices/galaxy-s4/apq8064.h` |
| `pexpert/arm/pe_identify_machine.c` | the board's setup of its timer and a `tbd_ops` for it |
| `osfmk/arm/machine_routines_asm.s` | the board's timer entry (`fleh_fiq_t8002` for T8002) and its get and set decrementer routines |

Three things in the kernel are about *who the CPU says it is*, and they must say "A6":

- `osfmk/arm/proc_reg.h`: the `ARMA7` block hard-codes `__ARM_SUB_ARCH__` as `CPU_ARCH_ARMv7k`. That
  becomes the kernel's `cpu_subtype` (`osfmk/arm/cpu.c` already maps v7s). It has to be `armv7s`:
  `grade_binary` in `bsd/dev/arm/kern_machdep.c` runs an `armv7s` slice on a v7s host and falls back
  to `armv7`, but a v7k host accepts only `armv7k`, which is the Watch's ABI.
- `cpuid_get_cpufamily` (`osfmk/arm/cpuid.c`) knows ARM's, Intel's and Apple's parts and has nothing
  for Qualcomm (implementer 0x51; the Krait's part number is VERIFY). `CPUFAMILY_ARM_SWIFT` exists in
  `osfmk/mach/machine.h` and nothing uses it for a 32-bit part. User space picks its `memcpy` by it.
- The time. The 32-bit kernel keeps time with the generic timer: `ml_get_speculative_timebase` reads
  `CNTPCT`. The dtsi of the APQ8064 has the Qualcomm KPSS timer and no generic timer, so (VERIFY, with
  ID_PFR1 on the phone) those reads would trap. XNU has a seam for the decrementer: `ml_init_timebase`
  takes a `tbd_ops` (FIQ handler, get and set decrementer) and T8002 fills it with its own timer. The
  S4 fills it with the KPSS timer's GPT0, which interrupts as a PPI of the GIC, so as an IRQ and not a
  FIQ (T8002's handler, `fleh_fiq_t8002`, is a FIQ entry; the S4's is called from the GIC driver's IRQ
  path instead); the timebase read is replaced with a read of the memory-mapped DGT counter. The
  registers are in `devices/galaxy-s4/apq8064.h`.

## Will the iOS 10.3 user space run on that kernel

The user space calls the kernel by number. `tools/xnu-abi-diff.py` compares the machine-independent
tables of xnu-3789.70.16, the nearest release to iOS 10.3's kernel that was published (Apple's own iOS
10.3 kernel source is not, and the tables are shared between its macOS and iOS builds; anything only
iOS has is not covered), with each candidate. It counts what 3789 has, 400 BSD system calls, 52 Mach
traps and 316 MIG routines (the messages to the kernel's services), and says what became of each:

| Release | BSD calls: same / arguments changed / gone | Mach traps gone | MIG routines gone |
|---|---|---|---|
| xnu-4570.71.2 | 398 / 2 / 0 | 0 | 0 |
| xnu-6153.141.1 | 395 / 5 / 0 | 0 | 0 |
| xnu-7195.141.2 | 392 / 5 / 3 | 1 | 0 |
| **xnu-8020.140.41** | 391 / 6 / 3 | 1 | 0 |
| xnu-8796.121.2 (our base today) | 387 / 6 / 7 | 1 | 19, and one renamed |

(Three MIG routines are retired in every one of them; their ids are kept as skips, so nothing moved.)
The drift grows with the age of the release, slowly up to 8020. Our current base is worse than 8020
for this user space even before its 32-bit code is counted: it also drops
`shared_region_map_and_slide_np` (438), which the dyld of that time used to map the shared cache
(VERIFY), and the Mach lock sets and the old memory-object interfaces.

For 8020, the exceptions, one by one:

- Six calls take different arguments, as the tool compares them (by the spelling of the types). Read
  against the 8020 source, five do not matter on a 32-bit machine: `guarded_open_np` and
  `guarded_open_dprotected_np` spell a pointer as `user_addr_t`, which is the same 32 bits there;
  `bsdthread_terminate`'s last argument now holds a port name or an address, and the kernel tells them
  apart (its comment calls that a compatibility hack, which is what the old caller needs); `gethostuuid`
  lost a third argument that the kernel now ignores; `sigreturn` gained a token that the kernel checks
  only in a process whose first `sigaction` sets `SA_VALIDATE_SIGRETURN_FROM_SIGTRAMP` (0x0400). The
  old libc never does (3789's `signal.h` stops at 0x0200), and that first call turns the check off for
  the process. The sixth, `persona`, reads an added `path` argument that the old libc does not pass;
  that one wants a shim in the BSD layer (VERIFY who calls it).
- Three calls are gone: `watchevent`, `waitevent`, `modwatch` (231 to 233). Whether iOS 10.3's user
  space calls them is VERIFY.
- `vfork` exists in 8020 only under `CONFIG_VFORK`, which no configuration in the tree defines. iOS's
  headers mark it unavailable, so its user space should not call it (VERIFY).
- The Mach trap `_kernelrpc_mach_port_destroy_trap` (-17) is gone. 3789's `mach_port_destroy` calls the
  trap first and falls back to the MIG message only on `MACH_SEND_INVALID_DEST`; 8020 answers an
  unused trap with `KERN_INVALID_ARGUMENT`, so the fallback never runs and `mach_port_destroy` fails.
  The trap has to come back: its function is in `osfmk/ipc/mach_kernelrpc.c` of xnu-6153, which still has
  it, with its entries in `osfmk/kern/syscall_sw.c` and `osfmk/mach/syscall_sw.h`.
- Three MIG routines are retired in 8020 (`host_priv` 421 and 422, `set` and `get_dp_control_port`,
  and `mach_host` 208, `host_zone_info`). Their ids are kept, so nothing else moved; a caller gets an
  error. On macOS `zprint` and the dynamic pager were their callers; iOS's are VERIFY.

The machine-dependent half is not in the tool. The commpage (`osfmk/arm/cpu_capabilities.h`) can be
compared only between the first release that has an ARM one (4570) and 8020: of the 32 addresses in
4570, 28 are at the same offset in 8020, two are boundary fillers that moved (`_COMM_PAGE_UNUSED0`,
`_COMM_PAGE_END`) and two are retired (`_COMM_PAGE_SCHED_GEN` at 0x28 and `_COMM_PAGE_SPIN_COUNT` at
0x2C, unused slots in 8020, so they should read as zero: VERIFY); 9 names are new. That is a lower
bound for 3789 to 8020. The thread
state (what `sigreturn` and exceptions carry) and the Mach-O and dyld expectations of iOS 10.3 were
not compared.

What this shows: the call numbers and argument lists that user space was built with are almost all
still there. What it does not show: that the behaviour behind them is the same. The kernel side of
the pthread work queues, of `kevent_qos`, of the memory-pressure and jetsam interfaces and of the
coalitions changed between 3789 and 8020 with the same numbers; that is Stage 4 below and is where
the risk is.

## The phone

Every address, interrupt and register in `devices/galaxy-s4/apq8064.h` has the place it came from next
to it: the APQ8064's device tree in mainline Linux, the mainline driver for a block, the mainline patch
that adds the Galaxy S4 (it was tested by its author on a GT-I9505), or LineageOS's board file for the
boot image. The S4's own Android kernel is a board-file kernel, so there is no device tree on the
phone to read (the POCO's `devices/poco-x5-pro/pull-soc.sh` pulls one). `devices/galaxy-s4/pull-soc.sh`
asks a running S4 over `adb` for what the numbers are lacking.

| Block | In `apq8064.h` | State |
|---|---|---|
| Interrupt controller | QGIC2 at 0x02000000 (distributor) and 0x02002000 (CPU interface) | from the dtsi |
| Timer | KPSS timer at 0x0200a000, 27 MHz, GPT0 at 32768 Hz as the clock event, the DGT as the clock source | from the dtsi and the mainline driver; never run here |
| Console | UART DM on GSBI7 at 0x16640000, 115200 baud, GPIOs 82 and 83 | from the mainline S4 patch; how to reach those pins on a retail phone: VERIFY |
| Storage | eMMC on SDCC1 at 0x12400000; the microSD slot probably SDCC3 at 0x12180000 | from the dtsi; which controller the slot uses: VERIFY |
| USB | ChipIdea at 0x12500000 | from the dtsi; which controller the cable uses: VERIFY |
| Display | MDP4 at 0x05100000, DSI at 0x04700000 | the panel and whether the bootloader leaves a framebuffer: VERIFY |
| GPU | Adreno 320 at 0x04300000 | not before Stage 5 |
| Memory | RAM from 0x80000000; ramoops at 0x88d00000 | the size: VERIFY |
| Boot image | base 0x80200000, kernel at 0x80208000, ramdisk at 0x82200000, tags at 0x80200100, page 2048; BOOT is 10 MiB | from LineageOS; RECOVERY's size: VERIFY |

Also open: the Krait's part number and whether its cores have the generic timer (`pull-soc.sh` reads
`/proc/cpuinfo`; ID_PFR1 bits 19:16 from a bare-metal test settle the timer); how the other three cores
are started (the per-core ACC and SAW blocks, probably with a call into TrustZone: read the mainline
`platsmp.c`); what state the bootloader enters the kernel in (MMU, caches, secure or not); whether
the ATAGS at 0x80200100 are all there is.

## Getting a payload onto the phone

The POCO's `fastboot boot` has no counterpart on a Samsung. Every way in writes flash: with Odin or
Heimdall in Download mode, a boot image goes into a partition. Writing BOOT replaces Android's kernel;
writing RECOVERY leaves Android as it was and costs a key combination at power-on, so **RECOVERY is
the slot to use**. Either way it may trip the Knox warranty bit, and `devices/galaxy-s4/README.md`
says what to check before you do it. `devices/galaxy-s4/mkbootimg.sh` makes the image and refuses one
over 10 MiB.

An XNU kernel and an iOS system do not fit into 10 MiB, so what is flashed is only the first stage:

| | What is flashed | What it needs | State |
|---|---|---|---|
| A | our own loader, which reads the rest from the microSD card | an SD driver (SDCC3) in the loader, which Stage 3 needs anyway | the plain path |
| B | a small Linux as a launch pad (mainline with the S4 device tree, whose commit message reports the UART, USB peripheral mode with networking, the LED and the buttons working on a GT-I9505; the SD card is not in that list), which loads our loader with `kexec` | a kernel built for it; `kexec` taking our loader (VERIFY) | quickest to iterate: flashed once, then everything is copied over USB |
| C | our own loader with a USB device driver (ChipIdea) of its own, so that the host can push the payload as `fastboot boot` does | a USB gadget driver | the most work |

B gets the earliest feedback; A is what a finished port would be. The container for the payload
(`xnuloader/mkpayload.py`) already exists for the 64-bit loader.

## Stages

Each stage ends in something that can be run and checked. None has been reached.

| Stage | Ends with | The phone |
|---|---|---|
| 0 | a bare-metal ARM program, flashed to RECOVERY, says something that can be read back. Console: the UART if its pins can be reached, or a record left in the ramoops region and read from Android's `/sys/fs/pstore` after a reboot (VERIFY that the bootloader leaves RAM alone). `pull-soc.sh` has been run and the VERIFY lines in `apq8064.h` are settled | yes |
| 1 | XNU 8020 with our patch and a generic 32-bit machine (GICv2 and the generic timer) builds, boots in QEMU's `virt` (Cortex-A15; VERIFY that it has what the 32-bit start code needs), and a 32-bit `armv7s` `hello` runs as the first process: the 32-bit counterpart of `make qemu-open`. This is where most of the kernel work can be done | no |
| 2 | the Krait configuration: the same `hello` on the S4, one core, timer and interrupts from the KPSS and the QGIC | yes |
| 3 | a driver for the SD card, a framebuffer text console, the root filesystem mounted read-only | yes |
| 4 | the shims above; iOS 10.3's own `launchd` starts and stays up, with the services it needs | yes |
| 5 | SpringBoard: the GPU (Adreno 320 through Mesa, if it works), touch, the buttons | yes |

Stage 1 is what makes the rest possible without a phone on the desk, and is also the stage where the
64-bit assumptions of our own kernel files (`osfmk/arm64/`, `pexpert/arm64/`, the 53 driver files, the
APFS reader) have to be found one by one; which of them even compile for 32 bits was not checked.

## What is in the repository for this

| Where | What |
|---|---|
| `devices/galaxy-s4/` | `apq8064.h` (the constants), `mkbootimg.sh`, `pull-soc.sh`, `check.sh`; its README is the map |
| `tools/xnu-arm32-survey.sh` | which XNU releases carry 32-bit ARM code, and in what state |
| `tools/xnu-port-check.py` | how much of `xnu/hakios.patch` fits another XNU tree |
| `tools/xnu-abi-diff.py` | what an older user space would find missing in a newer kernel |
| `make s4-check` | the self-test of all of the above: no phone, no network, nothing of Apple's or Samsung's |

The self-test shows that the tools measure what they say they measure (it runs them on miniature XNU
trees and on a synthetic `adb`, and breaks them on purpose to see the test fail). It does not show that
anything boots.

## Reproducing the measurements

```bash
# 1. which releases have 32-bit ARM code (file lists only; needs git and a route to GitHub)
tools/xnu-arm32-survey.sh

# 2. how much of the patch fits a release
git clone --depth 1 --branch xnu-8020.140.41 https://github.com/apple-oss-distributions/xnu.git /tmp/xnu-8020
tools/xnu-port-check.py /tmp/xnu-8020 --list

# 3. what the iOS 10.3 user space would miss (needs clang for the MIG part)
git clone --depth 1 --branch xnu-3789.70.16 https://github.com/apple-oss-distributions/xnu.git /tmp/xnu-3789
tools/xnu-abi-diff.py /tmp/xnu-3789 /tmp/xnu-8020

# 4. the commpage, between the first ARM release and 8020
git clone --depth 1 --branch xnu-4570.71.2 https://github.com/apple-oss-distributions/xnu.git /tmp/xnu-4570
cpg() { sed -n -E 's/^#define[[:space:]]+(_COMM_PAGE_[A-Z0-9_]+)[[:space:]]+\(_COMM_PAGE_START_ADDRESS\+(0x[0-9A-Fa-f]+)\).*/\1 \2/p' "$1/osfmk/arm/cpu_capabilities.h" | sort; }
diff <(cpg /tmp/xnu-4570) <(cpg /tmp/xnu-8020)

# 5. the scaffold itself
make s4-check
```

The same commands as make targets: `make xnu-survey`, `make xnu-port-check TREE=/tmp/xnu-8020`,
`make xnu-abi-diff OLD=/tmp/xnu-3789 NEW=/tmp/xnu-8020`, `make s4-survey` (a phone on `adb`).

## Not established

The VERIFY items above, in the order they block things:

- that the Krait has no generic timer (ID_PFR1), and its part number;
- how the S4 can be given a console: where the UART's pads are, or whether ramoops survives a reboot;
- RAM size and map (`/proc/iomem`), RECOVERY's size, which controllers the microSD slot and the USB
  cable use, whether the bootloader leaves a framebuffer behind, and the state it enters the kernel in;
- that the bootloader accepts an unsigned image on the model in hand, and what the Knox bit does;
- how the other cores are started;
- whether QEMU's `virt` with a Cortex-A15 runs XNU's 32-bit start code, and whether `kexec` can load our
  loader (Stage 1 and option B);
- the file system and the device-tree format of the 10.3 IPSW, and the size of its expanded root
  filesystem;
- the behaviour (and not only the numbers) of the kernel interfaces listed in the last two paragraphs of
  "Will the iOS 10.3 user space run on that kernel", and the commpage and thread state of iOS 10.3 itself;
- the size of a 32-bit development XNU kernel, against the 10 MiB BOOT partition;
- an SDK for building our own 32-bit user-space programs for iOS 10.3 (the xnu-deps build lays out the
  16.5 one).

## Sources

- The iPhone Wiki's key pages for each build (they say which files are encrypted):
  <https://www.theiphonewiki.com/wiki/Hoodoo_9B206_(iPhone4,1)>,
  <https://www.theiphonewiki.com/wiki/BrightonMaps_10B329_(iPhone4,1)>,
  <https://www.theiphonewiki.com/wiki/Sochi_11D257_(iPhone5,4)>,
  <https://www.theiphonewiki.com/wiki/Genoa_13G36_(iPhone5,1)>,
  <https://theiphonewiki.com/wiki/Greensburg_14G60_(iPhone5,3)>.
- IPSW sizes: <https://www.ipsw.io/download/iPhone5,3/14G60>, <https://ipsw.me/download/iPhone5,1/14G60/>.
- Apple's open-source XNU: <https://github.com/apple-oss-distributions/xnu>, tags `xnu-3789.70.16`,
  `xnu-4570.71.2`, `xnu-6153.141.1`, `xnu-7195.141.2`, `xnu-8020.140.41`, `xnu-8796.121.2`; the file
  system: <https://github.com/apple-oss-distributions/hfs>.
- Mainline Linux: `arch/arm/boot/dts/qcom/qcom-apq8064.dtsi` and `drivers/clocksource/timer-qcom.c`; the
  patch "ARM: dts: qcom: Add Samsung Galaxy S4" (<https://lkml.rescloud.iu.edu/hypermail/linux/kernel/2606.1/04622.html>).
- LineageOS: the install page for the I9505 (<https://wiki.lineageos.org/devices/jfltexx/install/>) and
  `BoardConfigCommon.mk` of `android_device_samsung_jf-common` for the boot image layout;
  postmarketOS's `device-samsung-jflte` (<https://pkgs.postmarketos.org/package/master/postmarketos/armv7/device-samsung-jflte>).
