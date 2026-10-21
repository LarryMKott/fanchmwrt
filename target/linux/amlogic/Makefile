# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2006-2013 OpenWrt.org

include $(TOPDIR)/rules.mk

BOARD:=amlogic
BOARDNAME:=Amlogic
BOARDNAME:=Amlogic Meson family
FEATURES:=boot-part ext4 audio usb fpu legacy-sdcard squashfs usbgadget display gpio fpu pci pcie
SUBTARGETS:=meson8b mesongx

KERNEL_PATCHVER:=6.12
# 6.18 LTS is the testing line: default build stays 6.12; setting
# CONFIG_TESTING_KERNEL=y in .config switches to 6.18 (patches-6.18/config-6.18).
KERNEL_TESTING_PATCHVER:=6.18

define Target/Description
	Build firmware image for Amlogic Meson SoC devices.
	Currently produces SD Card/USB disk image.
endef

include $(INCLUDE_DIR)/target.mk

DEFAULT_PACKAGES += \
	e2fsprogs \
	mkf2fs \
	block-mount \
	resize2fs \
	partx-utils \
	losetup htop

KERNELNAME:=Image dtbs

$(eval $(call BuildTarget))
