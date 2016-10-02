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

	debootstrap --foreign --no-check-gpg --include=ca-certificates --arch ${arch} ${release} ${rootfs} ${mirror}
	printf "Copy qemu-arm-static to ${rootfs}/usr/bin/"
	cp /usr/bin/qemu-arm-static ${rootfs}/usr/bin/
	LANG=C chroot ${rootfs} /debootstrap/debootstrap --second-stage
	
	mount ${bootp} ${bootfs}
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

### clean up
umount ${bootp}
umount ${rootp}
kpartx -d ${image}
