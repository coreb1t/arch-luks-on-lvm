#!/bin/bash
#
# Arch Linux installation script with full drive automatic partitioning full luks on LVM encryption 
# 
# Author: coreb1t
# Version: 0.2.1

# How to convert to MBR
https://superuser.com/questions/1250895/converting-between-gpt-and-mbr-hard-drive-without-losing-data

# ===== configuration =====
dev="/dev/sda"
boot_partition="/dev/sda1"
lvm_partition="/dev/sda2"
root_size=65 # GB
swap_size=12 # GB
hostname=myhost
add_packages="grub efibootmgr lvm2 sudo vim bash-completion zsh wget git dhclient net-tools"
user="newuser"

# ====== colors ========
WHITE_BOLD="\e[1m\e[37m"
GREEN="\e[32m"
GREEN_BOLD="\e[1m\e[32m"
RED="\e[31m"
RED_BOLD="\e[1m\e[31m"
RESET="\e[0m"


function info_green(){
	echo -e "${GREEN_BOLD}${1}${RESET}"
}

function info_white(){
	text=$1
	echo -e "${WHITE_BOLD}$text${RESET}"
}

# info without new line
function info_ok(){
	text=$1
	echo -e -n "${WHITE_BOLD}$text${RESET}"
}

function ok(){
	info_green "[OK]"
}

function warning(){
	echo -e "${RED_BOLD}${1}${RESET}"
}



# --- installation --- 
warning "\nPlease edit the configuration before continue !!!"
		info_green "\n===== Configuration ====="

		info_white "user:     \t$user"
		info_white "hostname: \t$hostname\n"
		info_white "device:   \t$dev"
		info_white "boot:     \t$boot_partition"
		info_white "lvm:      \t$lvm_partition LUKS encrypted"
		info_white "          \t* root ($root_size GB)"
		info_white "          \t* swap ($swap_size GB)"
		info_white "          \t* home (100%FREE)\n"

info_white "\tPress any key to continue"
read keyboard  

info_green "\nDid you setup the keyboard layout?"
info_white "(command: loadkeys de-latin1)" 
info_white "\n\tPress any key to continue"
read keyboard  


info_green "Do you want to start with Arch Linux installation (y/n)? "

read answer
if echo "$answer" | grep -iq "^y" ;then

	info_white "\n\t Installation steps:"
	info_white "\t 1) Live USB Environment"
	info_white "\t 2) Chrooted Environment\n"

   	info_green "Please enter the step number (1|2): "

	read answer1
	if echo "$answer1" | grep -iq "^1" ;then

		info_green "===== Step 1 (Live USB Environment) =====\n"

		######################### BEGIN - in LIVE ARCH LINUX CONFIGURATION ######################################

		# setup wifi
		# ping -q -w 1 -c 1 archlinux.org > /dev/null && info_white "internet connection: ok" || warning "internet connection: not connected"; wifi-menu

		info_white "[+] Checking internet connection ... "
		info_white "(if required use wifi-menu command to setup Wi-Fi)\n"
		info_white "\tCurrent IP: "
		ip link # show current ip

		info_white "\n\tPress any key to continue" 
		read input

		info_ok "[+] Updating system clock ... "
		timedatectl set-ntp true
		ok

		info_white "\nPlease create 2 partitions on the harddrive $dev" 
		# cfdisk /dev/sda
		info_green "\t boot partition [type 83] ($boot_partition) at least 1024MB (set as Linux filesystem and bootable)" 
		info_green "\t lvm  partition [type 8e] ($lvm_partition) use 100% from free space (set type as linux LVM) \n"
		
		info_white "\tPress any key to continue" 
		read input

		cfdisk $dev

		# print partitioning info
		sda1_size=$(fdisk -l $dev | grep $boot_partition | awk -F ' ' '{print $6}') # because of bootable flag
		sda2_size=$(fdisk -l $dev | grep $lvm_partition | awk -F ' ' '{print $5}')
		warning "\nPlease edit the configuration before continue (if required) !!!"
		info_green "\n--- configuration ---"
		info_white "device: \t$dev"
		info_white "boot:   \t$boot_partition ($sda1_size)"
		info_white "lvm:    \t$lvm_partition ($sda2_size) LUKS encrypted"
		info_white "        \t* root ($root_size GB)"
		info_white "        \t* swap ($swap_size GB)"
		info_white "        \t* home (100%FREE)\n"
		
		info_white "\n\tPress any key to continue"	
		read config  


		info_white "[+] Unmouting partitions ... "
		umount /mnt/boot
		umount /mnt
		umount /mnt/home
		rm -rf /mnt
		mkdir /mnt
		info_ok "[+] Unmouting partitions ... "; ok

		info_white "[+] Formating $boot_partition ... "
		# dd if=/dev/zero of=/dev/sda1 bs=1M status=progress
		# mkfs.ext4 /dev/sda1
		# mkdir /mnt/boot
		# mount /dev/sda1 /mnt/boot
		dd if=/dev/zero of=$boot_partition bs=1M status=progress 2>/dev/null
		mkfs.ext4 $boot_partition
		mkdir /mnt/boot
		mount $boot_partition /mnt/boot
		info_ok "[+] Formating $boot_partition ... "; ok



		info_white "[+] Preparing LVM ... "
		# https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system#LVM_on_LUKS


		# remove old LVM volumes

			# remove logic volumes
			for i in $(lvdisplay | grep -i path'' | awk -F ' ' '{print $3}'); do lvremove $i; done
			# remove volume group
			vgremove $(vgdisplay | grep -i name | awk -F ' ' '{print $3}')
			# remove physical volume
			pvremove $(pvdisplay | grep -i 'pv name' | awk -F ' ' '{print $3}')

		# pvcreate /dev/sda2
		# vgcreate MyVol /dev/sda2
		# lvcreate -L 10G -n lvroot MyVol
		# lvcreate -L 500M -n swap MyVol
		# lvcreate -L 500M -n tmp MyVol
		# lvcreate -l 100%FREE -n home MyVol

		pvcreate $lvm_partition
		vgcreate MyVol $lvm_partition
		lvcreate -L ${root_size}G -n lvroot MyVol
		lvcreate -L ${swap_size}G -n swap MyVol
		lvcreate -l 100%FREE -n home MyVol
		info_ok "[+] Preparing LVM ... "; ok


		info_white "[+] Configuring LUKS ... "
		# cryptsetup luksFormat -c aes-xts-plain64 -s 512 /dev/mapper/MyVol-lvroot
		# cryptsetup open /dev/mapper/MyVol-lvroot root
		# mkfs.ext4 /dev/mapper/root
		# mount /dev/mapper/root /mnt

		# LUKS root
		cryptsetup luksFormat -c aes-xts-plain64 -s 512 /dev/mapper/MyVol-lvroot
		cryptsetup open /dev/mapper/MyVol-lvroot root
		mkfs.ext4 /dev/mapper/root
		mount /dev/mapper/root /mnt

		mount | grep -w '/dev/mapper/root' 
		if [[ $? != 0 ]]; then
			warning "\n[-] Crypted volume (lvm-root) not created, try again"
			warning "[-] Installation canceled"
			exit
		fi

		mkdir /mnt/etc
		
		# mkdir -m 700 /etc/luks-keys
		# dd if=/dev/random of=/etc/luks-keys/home bs=1 count=256 status=progress

		# cryptsetup luksFormat -v -s 512 /dev/mapper/MyVol-home /etc/luks-keys/home
		# cryptsetup -d /etc/luks-keys/home open /dev/mapper/MyVol-home home
		# mkfs.ext4 /dev/mapper/home
		# mount /dev/mapper/home /home

		# LUKS home
		mkdir -m 700 /mnt/etc/luks-keys
		dd if=/dev/random of=/mnt/etc/luks-keys/home bs=1 count=256 status=progress

		cryptsetup luksFormat -v -s 512 /dev/mapper/MyVol-home /mnt/etc/luks-keys/home
		cryptsetup -d /mnt/etc/luks-keys/home open /dev/mapper/MyVol-home home
		mkfs.ext4 /dev/mapper/home
		mkdir /mnt/home
		mount /dev/mapper/home /mnt/home

		mount | grep -w '/dev/mapper/home' 
		if [[ $? != 0 ]]; then
			warning "\n[-] Crypted volume (lvm-home) not created, try again"
			warning "[-] Installation canceled"
			exit
		fi

		info_ok "[+] Configuring LUKS ... "; ok
	

		info_ok "[+] Configuring fstab and crypttab ... "
		fstab="/mnt/etc/fstab"
		touch $fstab
		echo '/dev/mapper/root        /       ext4            defaults        0       1' >> $fstab
		echo "$boot_partition              /boot   ext4            defaults        0       2" >> $fstab
		echo '/dev/mapper/swap        none    swap            sw              0       0' >> $fstab
		echo '/dev/mapper/home        /home   ext4            defaults        0       2' >> $fstab

		crypttab="/mnt/etc/crypttab"
		cp /etc/crypttab $crypttab
		echo 'swap	/dev/mapper/MyVol-swap   /dev/urandom	swap,cipher=aes-xts-plain64,size=256' >> $crypttab
		echo 'home	/dev/mapper/MyVol-home   /etc/luks-keys/home' >> $crypttab
		ok


		# info_white "[+] Refreshing mirrorlist ... "
		# echo "you can cancel the process if it takes to long. 6 fastest mirrors will be writted to /etc/pacman.d/mirrorlist (ctrl + C)"
		# cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup
		# rankmirrors -n 6 /etc/pacman.d/mirrorlist.backup > /etc/pacman.d/mirrorlist
		# info_ok "[+] Refreshing mirrorlist ... "; ok

		info_white "[+] Installing the base packages ... "
		pacstrap -K /mnt base linux linux-firmware
		info_ok "[+] Installing the base packages ... "; ok
		


		warning "\nchange root directory before continue !!!\n"
		cp $0 /mnt/
		info_white "coping installation script $0 to /mnt"
		info_white "command: arch-chroot /mnt"
		info_white "run $0 again and choose chrooted env\n"

		exit		

		######################### END - in LIVE ARCH LINUX CONFIGURATION ######################################
			
	fi


	
	if echo "$answer1" | grep -iq "^2" ;then

		info_green "===== Step 2 (Chrooted Environment)=====\n"

		######################### BEGIN - CHROOTED ENV CONFIGURATION ######################################

		# setup time zone
		ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime 
		hwclock --systohc

		# setup locale
		sed -i "s/#en_US ISO-8859-1/en_US ISO-8859-1/g" /etc/locale.gen
		sed -i "s/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g" /etc/locale.gen
		sed -i "s/#de_DE.UTF-8 UTF-8/de_DE.UTF-8 UTF-8/g" /etc/locale.gen
		sed -i "s/#de_DE@euro ISO-8859-15/de_DE@euro ISO-8859-15/g" /etc/locale.gen
		locale-gen

		echo "KEYMAP=de-latin1" > /etc/vconsole.conf
		echo $hostname > /etc/hostname

		echo "127.0.1.1	$hostname.localdomain	$hostname"  >> /etc/hosts
		info_ok "Setup time zone, locale, vconsole, hostname ... "; ok

		info_white "[+] Installing additional software ... "
		pacman -Sy $add_packages

		# add keyboard keymap lvm2 encrypt HOOKS to mkinitcpio.conf 
		sed -i "s/HOOKS=.*/HOOKS=\"base udev autodetect keyboard keymap modconf block lvm2 encrypt filesystems fsck\"/g" /etc/mkinitcpio.conf
		info_white "[+] Creating initramfs ..."
		mkinitcpio -p linux
		info_ok "[+]Creating initramfs ... "; ok

		info_white "[+] Configuring the boot loader (LUKS) ... "
		# GRUB_CMDLINE_LINUX="cryptdevice=/dev/sdb2:lvmpool root=/dev/mapper/lvmpool-root"
		# GRUB_CMDLINE_LINUX="cryptdevice=/dev/sdb2:MyVol root=/dev/mapper/MyVol-lvroot"
		# GRUB_CMDLINE_LINUX="cryptdevice=/dev/sda2:main root=/dev/mapper/main-root"
		#/dev/mapper/MyVol-lvroot
		#echo "cryptdevice=/dev/mapper/MyVol-lvroot:root root=/dev/mapper/root" >> /etc/default/grub
		sed -i "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"cryptdevice=\/dev\/mapper\/MyVol-lvroot:root root=\/dev\/mapper\/root\"/g" /etc/default/grub
		echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
		echo 'GRUB_PRELOAD_MODULES="lvm luks cryptodisk"' >> /etc/default/grub

		grub-mkconfig -o /boot/grub/grub.cfg
		grub-install --target=i386-pc $dev
		info_ok "[+] Configuring the boot loader (LUKS) ... "; ok


		info_white "[+] Changing root password ... "
		passwd
		info_ok "[+] Changing root password ... "; ok

		info_ok "[+] Adding user $user ... "
		useradd -m -G wheel -s /bin/zsh $user
		ok

		info_white "[+] Changing $user password ... "
		passwd $user
		info_ok "[+] Changing $user password ... "; ok
		

		# Blackarch installation
		info_green "Would you like to install blackarch (y/n)? "

		read answer
		if echo "$answer" | grep -iq "^y" ;then
			curl -O https://blackarch.org/strap.sh
			info_white "SHA1 Finderpring (from website)"
			curl https://blackarch.org/downloads.html -s  | grep 'The SHA1 sum should match:'
			info_white "SHA1 Finderpring (local file)"
			sha1sum strap.sh
			chmod +x strap.sh

			info_green "Are both SHA1 values the same? (y/n)"

			read answer
			if echo "$answer" | grep -iq "^y" ;then
				./strap.sh
				rm ./strap.sh
			fi
		fi


		info_green "Please finish the following steps"
		info_white "\t 1) Remove install scripts : rm $0"
		info_white "\t 2) Exit the chroot environment : exit"
		info_white "\t 3) Unmount all the partitions  : umount -R /mnt"

		######################### END - CHROOTED ENV CONFIGURATION ######################################
	fi

else
    warning "[-] Installation canceled"
fi
