#make clean
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- linux_card_defconfig
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all -j4
rm -rf ./out
mkdir out
cp arch/arm/boot/zImage ./out
cp arch/arm/boot/dts/sun8i-h3-orangepi-lite.dtb ./out/

cd ./out
mkimage -A arm -O linux -T kernel -C none -a 0x46000000 -e 0x46000000 -n linux-5.19.6 -d zImage uImage
