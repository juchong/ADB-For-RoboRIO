#!/bin/bash
if [[ $EUID -ne 0 ]]; then
	echo "Please run this script with administrator privileges. Sorry~ X///3"
	exit 1
fi
if hash apt-get >/dev/null; then
	echo "Installing FRC Toolchain..."
	apt-get update
	apt-get install git make wget cmake ninja-build git python3 libz-dev libssl-dev libusb-1.0-0-dev
	wget https://github.com/wpilibsuite/roborio-toolchain/releases/download/v2022-1/FRC-2022-Linux-Toolchain-7.3.0.tar.gz
	tar zxvf FRC-2022-Linux-Toolchain-7.3.0.tar.gz
	echo "Done."
	echo "Please run build.sh to build ADB for your RoboRIO."
else
        echo "APT is not installed. Please install APT on your computer."
	exit 1
fi
