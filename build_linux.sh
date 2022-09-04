make clean
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- linux_card_defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all -j4