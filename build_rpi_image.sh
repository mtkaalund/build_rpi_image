#!/bin/bash

# Which debian mirror and release that is used
mirror="http://archive.raspbian.org/raspbian"
release="jessie"
arch="armhf"
# size boot and environment directories
bootsize="64M"
current_pwd=`pwd`
buildenv="${current_pwd}/rpi"
rootfs="${buildenv}/root"
bootfs="${rootfs}/boot"
scripts="${current_pwd}/scripts"

current_date=`date +%Y%m%d`
image_size=4096
image=""
device=""
# Functions
check_host_packages() {
	packages=(binfmt-support qemu qemu-user-static debootstrap kpartx lvm2 dosfstools)
	apt-get -qq -o=Dpkg::Use-Pty=0 update

	for package in ${packages[@]}; do
		r_value=`dpkg-query -W -f='${Status}\n' $package`
		
		if [ "${r_value}" != "install ok installed" ]; then
			printf "Installing ${package}\n"
			apt-get -qq -o=Dpkg::Use-Pty=0 -y install ${package} > /dev/null
		else
			printf "${package} is installed\n"
		fi
	done
}

create_image() {
	mkdir -p ${buildenv}
	image="${buildenv}/raspbian_basic_${release}_${current_date}.img"

	if [ -f ${image} ]; then
		printf "Using the already existing image\n"
	else
		printf "Create image with the size of ${image_size} MB\n"

		dd if=/dev/zero of=${image} bs=1MB count=${image_size}
		
		printf "Creating devices"

		fdisk ${image} <<-FDF
		n
		p
		1
		
		+${bootsize}
		t
		c
		n
		p
		2
		
		
		w
		FDF
	fi
}

format_image() {
	device=`losetup -f --show ${image}`
	printf "Image mounted as ${device}\n"

	losetup -d ${device}
	device=`kpartx -va ${image} | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
	echo "Debug: ${device}"
	device="/dev/mapper/${device}"
	echo "Debug: ${device}"
	bootp=${device}p1
	echo "Debug: ${bootp}"
	rootp=${device}p2
	echo "Debug: ${rootp}"

	sleep 1	# need to make sure that it is ready
	mkfs.vfat ${bootp}
	mkfs.ext4 ${rootp}
}

create_debian() {
	printf "Create mounting point\n"
	mkdir -p ${rootfs}
	printf "Mounting ${rootp} to ${rootfs}\n"
	mount ${rootp} ${rootfs}

	printf "Creating directories\n"
	mkdir -p ${rootfs}/proc
	mkdir -p ${rootfs}/sys
	mkdir -p ${rootfs}/dev/pts
	mkdir -p ${rootfs}/scripts

	mount -t proc none ${rootfs}/proc
	mount -t sysfs none ${rootfs}/sys
	mount -o bind /dev ${rootfs}/dev
	mount -o bind /dev/pts ${rootfs}/dev
	mount -o bind ${scripts} ${rootfs}/scripts

	debootstrap --foreign --no-check-gpg --include=ca-certificates --arch ${arch} ${release} ${rootfs} ${mirror}
	printf "Copy qemu-arm-static to ${rootfs}/usr/bin/"
	cp /usr/bin/qemu-arm-static ${rootfs}/usr/bin/
	LANG=C chroot ${rootfs} /debootstrap/debootstrap --second-stage
	
	mount ${bootp} ${bootfs}
}

copy_configuration() {
	printf "Copying configs to ${rootfs}\n"
	mkdir -p ${rootfs}/etc/apt/
	mkdir -p ${rootfs}/etc/network/

	cat>${rootfs}/etc/apt/sources.list<<-EOF
	deb ${mirror} ${release} main contrib non-free rpi
	deb-src ${mirror} ${release} main contrib non-free rpi
	EOF

	cat>${rootfs}/etc/network/interfaces<<-EOF
	auto lo
	iface lo inet loopback

	auto eth0
	iface eth0 inet dhcp
	EOF

	cat>${rootfs}/etc/fstab<<-EOF
	proc			/proc	proc	defaults	0	0
	/dev/mmcblk0p1		/boot	vfat	defaults	0	0
	EOF

	cat>${rootfs}/hostname<<-EOF
	raspberrypi
	EOF
	
	cat>${rootfs}/modules<<-EOF
	vchiq
	snd_bcm2835
	EOF

	cat>${rootfs}/boot/cmdline.txt<<-EOF
	dwc_otg.lpm_enable=0 console=ttyAMA0,115200 kgdboc=ttyAMA0,115200 console=tty1 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait"
	EOF

	cat>${rootfs}/debconf.set<<-EOF
	console-common	console-data/keymap/policy	select Select keymap from full list
	console-common	console-data/keymap/full	select da-latin1-nodeadkeys
	EOF
}

run_stages() {
	LANG=C chroot ${rootfs} /scripts/third_stage.sh 
	LANG=C chroot ${rootfs} /scripts/cleanup.sh

	sync
	sleep 10
	cd
}
###################################
### 	Main program		###
###################################
# Check if it is run as root / sudo
if [ $EUID -ne 0 ]; then
	printf "This tool must be run as root\n"
	exit 1
fi

printf "Checking if host packages is installed\n"
check_host_packages
create_image
format_image
create_debian
copy_configuration
run_stages
### clean up
umount -l ${bootp}
umount -l ${rootfs}/scripts
umount -l ${rootfs}/dev/pts
umount -l ${rootfs}/dev
umount -l ${rootfs}/sys
umount -l ${rootfs}/proc
umount -l ${rootp}

dmsetup remove_all

if [ "${image}" != "" ]; then
	kpartx -d ${image}
	printf "Created image ${image}\n"
fi
