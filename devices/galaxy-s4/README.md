# Device: Samsung Galaxy S4 (jflte)

**Groundwork only: nothing here has run on an S4, and nothing boots.** This directory is what could be
done without the phone: the SoC's constants, a packer for the boot image the S4's bootloader reads, a
read-only survey that asks a real phone for what the constants lack, and a self-test of all of it. The
reasoning (which iOS, which kernel, what has to be written, in what order) and every number measured
for it are in `docs/s4-armv7-port.md`. As with the POCO X5 Pro, a phone is a directory like this one
and the kernel, loader and user space above it know nothing about the phone; unlike the POCO, this
phone is a 32-bit machine, which is most of the work.

"The S4" here is the **GT-I9505** ("jflte"): Qualcomm Snapdragon 600 (APQ8064T), four Krait 300 cores,
about 2 GB of RAM. The GT-I9500 is another SoC (Exynos) and is not covered.

| What | Where |
|---|---|
| SoC | Qualcomm APQ8064T: 32-bit ARMv7, QGIC2 interrupt controller, KPSS timer |
| The SoC's addresses, interrupts and registers | `apq8064.h`: plain constants, each with the place it was taken from (the device tree in mainline Linux, a mainline driver, the mainline S4 patch, LineageOS's board file) and a **VERIFY** where it is not established |
| A boot image for the phone | `mkbootimg.sh`: packs an Android boot image with the S4's addresses; refuses one over the BOOT partition's 10 MiB |
| What a real S4 says it is | `pull-soc.sh`: read-only, over `adb`; writes `soc-dump/` (git ignores it) |
| The self-test | `check.sh`: needs no phone, no network, nothing of Apple's or Samsung's |
| The phone's firmware | **not needed yet**, and never in the repository |
| Tools | `tools/xnu-arm32-survey.sh`, `tools/xnu-port-check.py`, `tools/xnu-abi-diff.py` (measure XNU releases, not the phone) |

## The self-test

```sh
make s4-check          # or devices/galaxy-s4/check.sh; a few seconds
```

It checks that the scripts parse and that this directory holds text only; that `apq8064.h` compiles for
a 32-bit ARM target and its derived numbers agree with each other; that clang's models of the Krait and
of the A6's Swift core have the same VFPv4, NEON and hardware divide (the reason the iOS for the A6 phones
is the one to run, `docs/s4-armv7-port.md`); that `mkbootimg.sh` writes the header the S4's bootloader
reads and refuses an image that would not fit; that `pull-soc.sh`, run against a synthetic `adb`, reaches
the right verdict and keeps serial numbers, IMEIs and MAC addresses out of what it writes; that the
three XNU tools classify a miniature XNU the way they say; and that the two documents name every file and
point to paths that exist. A check that cannot run here (no clang, no git) is printed as `skip` and does
not fail the run.

It shows that the tools measure what they say. It cannot show that anything boots.

## Asking a phone what it is

The S4's Android kernel is a board-file kernel, so unlike the POCO there is no device tree on the phone
to pull. What it has is `/proc` and `/sys`:

```sh
devices/galaxy-s4/pull-soc.sh        # the phone in Android, USB debugging on, on adb
```

It runs `cat`, `ls` and `getprop` on the phone and nothing else: no root, nothing is flashed or
changed. It asks `getprop` for a short list of properties rather than all of them, and blanks serial
numbers, IMEIs and MAC addresses out of what it saves, so that a `soc-dump/` can be attached to an
issue; read `summary.txt` first all the same. It prints the Krait's MIDR, the feature flags and
whether they are enough for the code of the A6 phones (`armv7s`), which timers Android has interrupts
for, the RAM ranges, the framebuffer, and every partition with its size. That settles most of the
**VERIFY** lines in `apq8064.h`; copy the answers into the header and the document by hand.

## Making a boot image

```sh
devices/galaxy-s4/mkbootimg.sh -o out.img --kernel FILE [--ramdisk FILE] [--cmdline STR]
```

The addresses (base 0x80200000, kernel at 0x80208000, ramdisk at 0x82200000, tags at 0x80200100, page
size 2048) are read from `apq8064.h`, so there is one copy of them. The "kernel" slot holds whatever
should run first: a bare-metal test program, our 32-bit loader, or a small Linux used as a launch pad.
It is not the room for an iOS system; the document says how a big payload gets into RAM. The packer
talks to no phone.

## Before you flash anything

Nothing in this repository flashes a phone. Putting the image on one (Odin or Heimdall, in Download
mode) is your decision, and it is not undone by a reboot:

- It overwrites the partition you write to. **Prefer RECOVERY to BOOT**: BOOT is Android's kernel,
  RECOVERY is not, so Android still starts as before and the image runs only when you ask for recovery
  mode (the usual key combinations are Home + Volume Up + Power for recovery and Home + Volume Down +
  Power for Download mode; check yours). Keep a copy of the stock image of the partition you overwrite.
- On a Samsung phone it normally trips the **Knox warranty bit**, and that stays tripped. `pull-soc.sh`
  prints the bit if the phone has the property.
- The size of RECOVERY has not been measured (**VERIFY**): `mkbootimg.sh` limits to BOOT's 10 MiB, and a
  bigger image for another partition needs an explicit `--max` after you have read the partition's size
  from `pull-soc.sh`.
- Some US carrier models have a locked bootloader (**VERIFY** on yours). A locked bootloader refuses
  unsigned images; getting around that is outside this project.
- Nothing of Samsung's or Apple's belongs in the repository: `.gitignore` is a whitelist, and
  `check.sh` fails if a file that is not text appears in this directory.

## Files

| File | |
|---|---|
| `README.md` | this |
| `apq8064.h` | the constants, with their sources |
| `mkbootimg.sh` | the boot-image packer |
| `pull-soc.sh` | the read-only survey of a phone |
| `check.sh` | the self-test |

MIT, as the file headers say. The numbers in `apq8064.h` are facts about the hardware, read from the
sources it names; no text of those sources (Linux's is GPL-2.0) and nothing of Samsung's is copied.
