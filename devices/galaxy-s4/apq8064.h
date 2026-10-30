/* SPDX-License-Identifier: MIT */
/*
 * apq8064.h -- the Qualcomm APQ8064 as it sits in the Samsung Galaxy S4 (GT-I9505, "jflte").
 *
 * Plain constants for the 32-bit loader and for the XNU platform code of the S4 port
 * (docs/s4-armv7-port.md). The S4's Android kernel is a board-file kernel, so there is no
 * device tree on the phone to read (compare devices/poco-x5-pro/pull-soc.sh). The numbers are
 * written down here instead, each with the place it was taken from:
 *
 *   dtsi     qcom-apq8064.dtsi of mainline Linux (arch/arm/boot/dts/qcom/), by node name
 *   driver   a mainline Linux driver, by file name: what the registers of a block do
 *   jflte    the patch "ARM: dts: qcom: Add Samsung Galaxy S4" (v3/v4, May-June 2026; the author
 *            tested it on a GT-I9505): the console and the ramoops region
 *   lineage  BoardConfigCommon.mk of LineageOS android_device_samsung_jf-common (boot image)
 *
 * Nothing is copied from Samsung's kernel sources. A line marked VERIFY is not established:
 * read it off a real phone first (devices/galaxy-s4/pull-soc.sh) before relying on it.
 *
 * GIC interrupt numbering: an SPI "n" in a device tree is GIC interrupt ID 32 + n, a PPI "n" is
 * 16 + n. APQ8064_SPI() and APQ8064_PPI() do the addition.
 */
#ifndef HAKIOS_S4_APQ8064_H
#define HAKIOS_S4_APQ8064_H

#define APQ8064_SPI(n)            (32u + (n))
#define APQ8064_PPI(n)            (16u + (n))

/* ---- CPU ------------------------------------------------------------------------------------ */
/* Four Krait cores (dtsi: cpus, compatible "qcom,krait", enable-method "qcom,kpss-acc-v1").
 * The secondary cores are started through the per-core ACC and SAW blocks, not through PSCI:
 * the first port runs on core 0 only. The Krait part number: VERIFY (/proc/cpuinfo). */
#define APQ8064_NUM_CPUS          4u
#define APQ8064_ACC0_BASE         0x02088000u   /* dtsi: clock-controller@2088000 (acc0) */
#define APQ8064_ACC_STRIDE        0x00010000u   /* acc1 0x2098000, acc2 0x20a8000, acc3 0x20b8000 */
#define APQ8064_SAW0_BASE         0x02089000u   /* dtsi: power-manager@2089000 (saw0) */
#define APQ8064_SAW_STRIDE        0x00010000u   /* saw1 0x2099000, saw2 0x20a9000, saw3 0x20b9000 */
#define APQ8064_L2CC_BASE         0x02011000u   /* dtsi: clock-controller@2011000 (l2cc) */

/* ---- Interrupt controller: Qualcomm QGIC2 ("qcom,msm-qgic2"), a GICv2 -------------------- */
#define APQ8064_QGIC_DIST_BASE    0x02000000u   /* dtsi: interrupt-controller@2000000, reg #1 */
#define APQ8064_QGIC_DIST_SIZE    0x00001000u
#define APQ8064_QGIC_CPU_BASE     0x02002000u   /* same node, reg #2 */
#define APQ8064_QGIC_CPU_SIZE     0x00001000u

/* ---- Timer: the KPSS timer ("qcom,kpss-timer") --------------------------------------------- */
/* The dtsi describes this timer and no ARM architected (generic) timer. XNU's 32-bit kernel
 * keeps time with the architected timer (CNTPCT, CNTV_TVAL), so the S4 needs a replacement for
 * those few accessors. Whether the cores have the architected timer at all: VERIFY (ID_PFR1).
 *
 * dtsi: timer@200a000, reg 0x0200a000 (0x100), clock-frequency 27 MHz, cpu-offset 0x80000,
 * interrupts PPI 1, 2, 3, all edge rising. What each register does is read off the mainline
 * driver (driver: drivers/clocksource/timer-qcom.c), which is the only description of this
 * timer that is not Qualcomm's or Samsung's own code; this port has not run on the hardware
 * yet, so all of it is VERIFY until it has.
 *
 * Two counters are used there. GPT0, which counts a fixed 32768 Hz, is the clock event: it
 * is armed through MATCH/ENABLE/CLEAR and raises the second of the three interrupts (PPI 2).
 * The DGT of CPU 0 is the clock source: a free-running counter that is read, never armed;
 * the driver divides its 27 MHz input by 4 through DGT_CLK_CTL. A core sees its own GPT0 at
 * BASE + 0x04; the DGT it reads is CPU 0's, at BASE + CPU_OFFSET + 0x24, from any core. */
#define APQ8064_KPSS_TIMER_BASE        0x0200a000u   /* dtsi: timer@200a000 */
#define APQ8064_KPSS_TIMER_SIZE        0x00000100u
#define APQ8064_KPSS_TIMER_REF_HZ      27000000u     /* dtsi: clock-frequency */
#define APQ8064_KPSS_TIMER_CPU_OFFSET  0x00080000u   /* dtsi: cpu-offset */
#define APQ8064_KPSS_TIMER_IRQ_FIRST   APQ8064_PPI(1) /* dtsi: PPI 1, 2, 3, edge rising */
/* registers of one counter, relative to that counter's own base (driver) */
#define APQ8064_KPSS_CNT_MATCH         0x00u
#define APQ8064_KPSS_CNT_COUNT         0x04u
#define APQ8064_KPSS_CNT_ENABLE        0x08u         /* bit 0 enable, bit 1 clear on match */
#define APQ8064_KPSS_CNT_CLEAR         0x0cu
/* GPT0: the clock event (driver) */
#define APQ8064_KPSS_GPT0_OFFSET       0x04u         /* from BASE */
#define APQ8064_KPSS_GPT_HZ            32768u
#define APQ8064_KPSS_GPT0_IRQ          APQ8064_PPI(2) /* the second interrupt of the node */
#define APQ8064_KPSS_STS_OFFSET        0x88u         /* from BASE: status; bit 10 = GPT0 clear pending */
#define APQ8064_KPSS_STS_GPT0_CLR_PEND (1u << 10)
/* DGT of CPU 0: the clock source (driver) */
#define APQ8064_KPSS_DGT_OFFSET        0x24u         /* from BASE + CPU_OFFSET */
#define APQ8064_KPSS_DGT_CLK_CTL       0x10u         /* from the DGT; value 3 divides the input by 4 */
#define APQ8064_KPSS_DGT_CLK_DIV_4     0x3u
#define APQ8064_KPSS_DGT_HZ            (APQ8064_KPSS_TIMER_REF_HZ / 4u)   /* 6.75 MHz */

/* ---- Console: GSBI7 UART DM ("qcom,msm-uartdm-v1.3") ---------------------------------------- */
/* jflte: stdout-path "serial0:115200n8" with serial0 = gsbi7_serial; pins gpio82 (TX), gpio83 (RX).
 * How to reach those pins on a retail phone: VERIFY. */
#define APQ8064_GSBI7_BASE        0x16600000u   /* dtsi: gsbi@16600000 (the GSBI control registers) */
#define APQ8064_GSBI7_UART_BASE   0x16640000u   /* dtsi: serial@16640000 */
#define APQ8064_GSBI7_UART_SIZE   0x00001000u
#define APQ8064_GSBI7_UART_IRQ    APQ8064_SPI(158)
#define S4_CONSOLE_BAUD           115200u
#define S4_CONSOLE_TX_GPIO        82u
#define S4_CONSOLE_RX_GPIO        83u

/* ---- Storage: eMMC on SDCC1 ----------------------------------------------------------------- */
/* dtsi: mmc@12400000, "arm,pl18x" with primecell periphid 0x00051180, 8-bit bus, up to 96 MHz,
 * BAM DMA at 0x12402000. jflte: eMMC on sdcc1 (vmmc from PM8921 l5, vqmmc from s4). */
#define APQ8064_SDCC1_BASE        0x12400000u
#define APQ8064_SDCC1_SIZE        0x00002000u
#define APQ8064_SDCC1_IRQ         APQ8064_SPI(104)
#define APQ8064_SDCC1_BAM_BASE    0x12402000u   /* dtsi: dma-controller@12402000 */

/* ---- SD card and USB ------------------------------------------------------------------------- */
/* Which controller the S4's microSD slot is wired to, and which USB controller the cable is
 * wired to, is not established: VERIFY. The dtsi has the candidates below. */
#define APQ8064_SDCC3_BASE        0x12180000u   /* dtsi: mmc@12180000, 4-bit, SD high speed (the slot, probably) */
#define APQ8064_SDCC3_SIZE        0x00002000u
#define APQ8064_SDCC3_IRQ         APQ8064_SPI(102)
#define APQ8064_SDCC3_BAM_BASE    0x12182000u   /* dtsi: dma-controller@12182000 */
#define APQ8064_USB1_BASE         0x12500000u   /* dtsi: usb@12500000, "qcom,ci-hdrc" (ChipIdea), ULPI PHY */
#define APQ8064_USB1_SIZE         0x00000200u
#define APQ8064_USB1_IRQ          APQ8064_SPI(100)

/* ---- Display and GPU ------------------------------------------------------------------------ */
#define APQ8064_MDP4_BASE         0x05100000u   /* dtsi: display-controller@5100000, "qcom,mdp4" */
#define APQ8064_MDP4_SIZE         0x000f0000u
#define APQ8064_MDP4_IRQ          APQ8064_SPI(75)
#define APQ8064_DSI0_BASE         0x04700000u   /* dtsi: dsi@4700000 */
#define APQ8064_DSI0_IRQ          APQ8064_SPI(82)
#define APQ8064_ADRENO_BASE       0x04300000u   /* dtsi: gpu@4300000, "qcom,adreno-320.2" */
#define APQ8064_ADRENO_SIZE       0x00020000u
#define APQ8064_ADRENO_IRQ        APQ8064_SPI(80)
/* The S4's panel and whether the bootloader leaves a live framebuffer behind: VERIFY. The
 * mainline jflte patch has no framebuffer node. */

/* ---- Other blocks the port will meet -------------------------------------------------------- */
#define APQ8064_TLMM_BASE         0x00800000u   /* dtsi: pinctrl@800000 (GPIO/pin mux), 90 GPIOs */
#define APQ8064_TLMM_SIZE         0x00004000u
#define APQ8064_TLMM_IRQ          APQ8064_SPI(16)
#define APQ8064_GCC_BASE          0x00900000u   /* dtsi: clock-controller@900000 */
#define APQ8064_GCC_SIZE          0x00004000u
#define APQ8064_MMCC_BASE         0x04000000u   /* dtsi: clock-controller@4000000 */
#define APQ8064_SSBI_PMIC_BASE    0x00500000u   /* dtsi: ssbi@500000, PMIC arbiter (PM8921) */
#define APQ8064_SSBI2_PMIC_BASE   0x00c00000u   /* dtsi: ssbi@c00000, PMIC arbiter (PM8821) */
#define APQ8064_RPM_BASE          0x00108000u   /* dtsi: rpm@108000 */

/* ---- Memory ---------------------------------------------------------------------------------- */
#define S4_RAM_BASE               0x80000000u   /* dtsi: the SMEM region starts here */
/* Size: VERIFY. The spec sheet says 2 GB; /proc/iomem on the phone decides. */
#define APQ8064_SMEM_BASE         0x80000000u   /* dtsi: reserved-memory smem@80000000, no-map */
#define APQ8064_SMEM_SIZE         0x00200000u
#define S4_RAMOOPS_BASE           0x88d00000u   /* jflte: reserved-memory ramoops@88d00000 */
#define S4_RAMOOPS_SIZE           0x00100000u
/* The RIVA (Wi-Fi/BT) firmware region of the generic dtsi, 0x8f000000 + 0x700000, is not
 * established for the S4: VERIFY against /proc/iomem. */

/* ---- Android boot image the S4's bootloader loads (lineage) --------------------------------- */
/* BOARD_KERNEL_BASE 0x80200000, --ramdisk_offset 0x02000000, BOARD_KERNEL_PAGESIZE 2048;
 * the kernel offset and tags offset are mkbootimg's defaults. */
#define S4_BOOT_BASE              0x80200000u
#define S4_BOOT_KERNEL_OFFSET     0x00008000u
#define S4_BOOT_RAMDISK_OFFSET    0x02000000u
#define S4_BOOT_TAGS_OFFSET       0x00000100u
#define S4_BOOT_PAGE_SIZE         2048u
#define S4_BOOT_KERNEL_ADDR       (S4_BOOT_BASE + S4_BOOT_KERNEL_OFFSET)    /* 0x80208000 */
#define S4_BOOT_RAMDISK_ADDR      (S4_BOOT_BASE + S4_BOOT_RAMDISK_OFFSET)   /* 0x82200000 */
#define S4_BOOT_TAGS_ADDR         (S4_BOOT_BASE + S4_BOOT_TAGS_OFFSET)      /* 0x80200100 */
/* lineage: BOARD_BOOTIMAGE_PARTITION_SIZE 10485760 (the BOOT partition). The size of the
 * RECOVERY partition: VERIFY. */
#define S4_BOOT_PARTITION_MAX     10485760u

#endif /* HAKIOS_S4_APQ8064_H */
