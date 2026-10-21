#!/bin/sh
# Copy running OpenWrt to eMMC for amlogic

. /lib/functions.sh
. /lib/functions/system.sh

include /lib/upgrade
NEWLINE="
"

function umount_disk() {
	local mounted
	local to="${1#/dev/}"
	umount "/dev/$to"* 2>/dev/null
	mounted="`mount | cut -d' ' -f1 | grep -Fm1 "/dev/$to"`"
	if [ -n "$mounted" ] ; then
		echo "can not umount $mounted" >&2
		return 1
	fi
	return 0
}

# Convert a user-supplied size to MiB.
#   61440 -> 61440 (MiB) | 60G / 60GB -> 61440 | 500M / 500MB -> 500 | 100% -> whole disk
parse_mib() {
	local v="$1" disk_mib="$2"
	case "$v" in
		*%)	echo "$disk_mib"; return ;;
	esac
	echo "$v" | awk '
		{
			unit = ""
			n = $0
			if (n ~ /[Gg]/) unit = "G"
			else if (n ~ /[Mm]/) unit = "M"
			gsub(/[^0-9.].*/, "", n)
			if (n == "") { print ""; exit }
			if (unit == "G") n = n * 1024
			printf "%d\n", n
		}'
}

function part_disk() {
	local to="${1#/dev/}"
	local disk_mib p2_end p3_end p3_spec ans v

	# Disk capacity in MiB (blockdev first, parted as fallback).
	disk_mib=$(blockdev --getsize64 "/dev/$to" 2>/dev/null)
	if [ -n "$disk_mib" ]; then
		disk_mib=$((disk_mib / 1048576))
	else
		disk_mib=$(parted -ms "/dev/$to" unit MiB print 2>/dev/null \
			| sed -n 's/^\/dev\/[^:]*:\([0-9]*\)MiB:.*/\1/p' | head -1)
	fi
	if [ -z "$disk_mib" ] || [ "$disk_mib" -le 0 ]; then
		echo "Unable to determine size of /dev/$to" >&2
		return 1
	fi

	# Default layout: p3 takes the rest of the disk.
	p2_end=388
	p3_end=$disk_mib

	echo ""
	echo "eMMC /dev/$to: ${disk_mib} MiB ($((disk_mib / 1024)) GiB)"
	echo ""
	echo "  #  start      end        size      role"
	echo "  1   68 MiB   132 MiB     64 MiB   boot: u-boot.emmc, kernel, dtb (fixed)"
	echo "  2  132 MiB  ${p2_end} MiB   $((p2_end - 132)) MiB  rootfs: squashfs, read-only"
	echo "  3  764 MiB  ${p3_end} MiB   $((p3_end - 764)) MiB  overlay: all writable data"
	echo ""
	echo -n "Use this default layout? [Y/n] "
	read ans

	if [ "$ans" = n ] || [ "$ans" = N ]; then
		echo -n "  p2 rootfs end (MiB, >=388) [388]: "
		read v
		[ -n "$v" ] && p2_end=$(parse_mib "$v" "$disk_mib")
		echo -n "  p3 overlay end (MiB / G / GB / % ) [100%]: "
		read v
		[ -n "$v" ] && p3_end=$(parse_mib "$v" "$disk_mib")
	fi

	[ -z "$p2_end" ] && p2_end=388
	[ -z "$p3_end" ] && p3_end=$disk_mib

	if [ "$p2_end" -lt 388 ]; then
		echo "ERROR: p2 end must be >= 388 MiB (rootfs needs 256 MiB)" >&2
		return 1
	fi
	if [ "$p3_end" -le 764 ]; then
		echo "ERROR: p3 end must be > 764 MiB" >&2
		return 1
	fi
	if [ "$p3_end" -gt "$disk_mib" ]; then
		echo "ERROR: p3 end ($p3_end MiB) exceeds disk ($disk_mib MiB)" >&2
		return 1
	fi

	# Let parted own the last-sector alignment when filling the disk.
	if [ "$p3_end" -eq "$disk_mib" ]; then
		p3_spec="100%"
	else
		p3_spec="${p3_end}MiB"
	fi

	echo ""
	echo "Creating partitions:"
	echo "  p1  68 MiB -> 132 MiB"
	echo "  p2 132 MiB -> ${p2_end} MiB"
	echo "  p3 764 MiB -> ${p3_spec}"

	dd if=/dev/zero of="/dev/$to" bs=512 count=1 conv=notrunc 2>/dev/null
	parted --script "/dev/$to" \
		mktable msdos \
		mkpart primary 68MiB 132MiB \
		mkpart primary 132MiB "${p2_end}MiB" \
		mkpart primary 764MiB "${p3_spec}"
}

function get_bootdisk() {
	local var=$1
	local diskdev
	export_bootdevice && export_partdevice diskdev 0 || {
		echo "Unable to determine upgrade device" >&2
		return 1
	}
	export "$var=$diskdev"
	return 0
}

function get_emmcs() {
	local disk index disks
	local bootdisk=$1

	index=1
    for disk in `cd /sys/block && ls | grep '^mmcblk' | grep -Ev 'mmcblk\d+boot\d+'`; do
        [[ "$bootdisk" = "$disk" ]] && continue
        [ -b /dev/$disk ] && [ "`cat /sys/block/$disk/size`" -gt 0 ] || continue
        local diskinfo="`parted -ms "/dev/$disk" unit GiB print 2>/dev/null | grep -m1 "^/dev/$disk:"`"
        [ -z "$diskinfo" ] && continue
        local size="`echo "$diskinfo" | cut -d: -f2`"
		# check disk greater than 2.8GB
        [ $(( `echo "${size%%GiB}" | sed 's/\.\(.\).*/ * 10 + \1/'` )) -ge 28 ] || continue
        local model="`echo "$diskinfo" | cut -d: -f7 | sed 's/"/_/g'`"
        disks="${disks}$index. $disk $size \"$model\"$NEWLINE"
		index=$(($index + 1))
    done
	echo "$disks"
	return 0
}

function get_emmc() {
	local index
	local var=$2
	local emmcs="$(get_emmcs $1)"
	[ -z "$emmcs" ] && {
		echo "Get eMMC list failed! (Maybe already running on eMMC? Current boot disk is $1)" >&2
		return 1
	}
	local count=$(echo "$emmcs" | wc -l)
	if [ "$count" -gt 1 ]; then
		while true; do
			echo "Found these eMMC devices:"
			echo "Index.  device  size  model"
			echo "$emmcs"
			echo -n "Select a disk to install (input index then press Enter): "
			read index || {
				echo "No input!" >&2
				exit 1
			}
			if [ -z "$index" ]; then
				echo "Empty input!"
			else
				echo "$emmcs" | grep -q "^${index}. " && break
				echo "Wrong index!"
			fi
		done
	else
		echo "Found eMMC device:"
		echo "Index.  device  size  model"
		echo "$emmcs"
		index=1
	fi
	local value=$(echo "$emmcs" | grep "^${index}. " | cut -d' ' -f 2)
	export "$var=$value"
}

function main() {
	local bootdisk yn partdev part partdevto to
	get_bootdisk bootdisk
	[ -z "$bootdisk" ] && return 1
	get_emmc $bootdisk to
	[ -n "$to" ] || return 1
	echo -ne "Will install to $to, confirm? y/N [n]\b\b"
	read yn
	if [ "$yn" = Y -o "$yn" = y ]; then
		echo ""
		echo "umount /dev/$to*"
		umount_disk "$to" || return 1
		echo "part /dev/$to"
		part_disk "$to" || return 1
		partprobe "/dev/$to"
		if export_partdevice partdev 1; then
			# umount /boot
			echo "try umount /boot"
			/bin/mount -o noatime,remount,ro /dev/$partdev
			/usr/bin/umount -R -d -l /dev/$partdev 2>/dev/null || /bin/umount -l /dev/$partdev
		fi
		sleep 1
		echo "copy rom data from /dev/$bootdisk to /dev/$to"
		for part in 1 2; do
			# copy boot and rootfs partitions
			export_partdevice partdev $part
			partdevto=${to}p$part
			echo "copy /dev/$partdev to /dev/$partdevto"
			dd if=/dev/$partdev of=/dev/$partdevto bs=1M conv=notrunc
		done
		# mark RESET overlay partition
		partdevto=${to}p3
		echo "mark /dev/$partdevto as RESET"
		echo "RESET000" | dd of="/dev/$partdevto" bs=512 count=1 conv=sync,fsync
		echo "All Done!"
	else
		echo "Bye!"
	fi
}

echo "Copy running OpenWrt to eMMC for amlogic"
echo ""

main
