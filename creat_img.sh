#!/bin/bash

# 设置颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
DEFAULT_KERNEL_DIR="/home/test/work/H5/linux/linux5.19.6_Quarkn"
DEFAULT_UBOOT_DIR="/home/test/work/H5/uboot/u-boot-2022-07/u-boot-2022.07"
DEFAULT_OUTPUT_DIR="$(pwd)/output"
DEFAULT_IMAGE_NAME="h5_luoorshi_sdcard.img"
DEFAULT_IMG_SIZE=8192
DEFAULT_BOOT_PART_SIZE=64
DEFAULT_ROOTFS_PART_SIZE=960

# 全局变量
CLEANUP_NEEDED=false
MOUNTED_DIRS=()
LOOP_DEV=""

# 错误处理函数
error_exit() {
    echo -e "${RED}错误: $1${NC}" >&2
    cleanup
    exit 1
}

# 警告函数（不会退出）
warning_msg() {
    echo -e "${YELLOW}警告: $1${NC}" >&2
}

# 清理函数
cleanup() {
    echo -e "${YELLOW}执行清理操作...${NC}"
    
    # 卸载所有挂载的目录
    for dir in "${MOUNTED_DIRS[@]}"; do
        if mountpoint -q "$dir" 2>/dev/null; then
            echo -e "${YELLOW}卸载 $dir...${NC}"
            sudo umount "$dir" 2>/dev/null || warning_msg "无法卸载 $dir"
        fi
    done
    
    # 删除挂载点目录
    [ -d "boot" ] && sudo rmdir boot 2>/dev/null || true
    [ -d "rootfs" ] && sudo rmdir rootfs 2>/dev/null || true
    
    # 释放循环设备
    if [ -n "$LOOP_DEV" ] && sudo losetup -a | grep -q "$LOOP_DEV"; then
        echo -e "${YELLOW}释放循环设备 $LOOP_DEV...${NC}"
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || warning_msg "无法释放循环设备 $LOOP_DEV"
    fi
    
    # 清理临时文件
    [ -f "boot.cmd" ] && rm -f boot.cmd
    
    CLEANUP_NEEDED=false
    MOUNTED_DIRS=()
    LOOP_DEV=""
}

# 信号处理
trap cleanup EXIT INT TERM

# 安全执行函数，带错误检查
safe_exec() {
    local cmd="$1"
    local description="$2"
    
    echo -e "${YELLOW}$description...${NC}"
    if ! eval "$cmd"; then
        error_exit "$description 失败"
    fi
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        error_exit "所需命令 '$1' 未安装"
    fi
}

# 显示使用说明
show_usage() {
    echo -e "${GREEN}使用方法:${NC}"
    echo "  $0 [选项]"
    echo ""
    echo -e "${GREEN}选项:${NC}"
    echo "  -k, --kernel-dir DIR     内核目录路径 (默认: $DEFAULT_KERNEL_DIR)"
    echo "  -u, --uboot-dir DIR      U-Boot目录路径 (默认: $DEFAULT_UBOOT_DIR)"
    echo "  -o, --output-dir DIR     输出目录路径 (默认: $DEFAULT_OUTPUT_DIR)"
    echo "  -n, --image-name NAME    输出镜像文件名 (默认: $DEFAULT_IMAGE_NAME)"
    echo "  -s, --img-size SIZE      镜像总大小(MB) (默认: $DEFAULT_IMG_SIZE)"
    echo "  -b, --boot-size SIZE     Boot分区大小(MB) (默认: $DEFAULT_BOOT_PART_SIZE)"
    echo "  -r, --rootfs-size SIZE   RootFS分区大小(MB) (默认: $DEFAULT_ROOTFS_PART_SIZE)"
    echo "  -h, --help               显示此帮助信息"
    echo ""
    echo -e "${GREEN}示例:${NC}"
    echo "  $0 -k /path/to/kernel -u /path/to/uboot -o ./my_output -s 2048"
    echo "  $0 --kernel-dir /home/user/kernel --img-size 512 --boot-size 128"
    echo ""
}

# 解析命令行参数
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kernel-dir)
                [ -z "$2" ] && error_exit "选项 $1 需要参数"
                KERNEL_DIR="$2"
                shift 2
                ;;
            -u|--uboot-dir)
                [ -z "$2" ] && error_exit "选项 $1 需要参数"
                UBOOT_DIR="$2"
                shift 2
                ;;
            -o|--output-dir)
                [ -z "$2" ] && error_exit "选项 $1 需要参数"
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -n|--image-name)
                [ -z "$2" ] && error_exit "选项 $1 需要参数"
                IMAGE_NAME="$2"
                shift 2
                ;;
            -s|--img-size)
                [ -z "$2" ] && error_exit "选项 $1 需要参数"
                IMG_SIZE="$2"
                shift 2
                ;;
            -b|--boot-size)
                [ -z "$2" ] && error_exit "选项 $1 需要参数"
                BOOT_PART_SIZE="$2"
                shift 2
                ;;
            -r|--rootfs-size)
                [ -z "$2" ] && error_exit "选项 $1 需要参数"
                ROOTFS_PART_SIZE="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                error_exit "未知参数 $1"
                ;;
        esac
    done
}

# 设置默认值（如果用户没有提供）
set_defaults() {
    KERNEL_DIR="${KERNEL_DIR:-$DEFAULT_KERNEL_DIR}"
    UBOOT_DIR="${UBOOT_DIR:-$DEFAULT_UBOOT_DIR}"
    OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
    IMAGE_NAME="${IMAGE_NAME:-$DEFAULT_IMAGE_NAME}"
    IMG_SIZE="${IMG_SIZE:-$DEFAULT_IMG_SIZE}"
    BOOT_PART_SIZE="${BOOT_PART_SIZE:-$DEFAULT_BOOT_PART_SIZE}"
    ROOTFS_PART_SIZE="${ROOTFS_PART_SIZE:-$DEFAULT_ROOTFS_PART_SIZE}"
}

# 验证配置参数
validate_config() {
    # 检查目录是否存在
    [ ! -d "$KERNEL_DIR" ] && error_exit "内核目录不存在: $KERNEL_DIR"
    [ ! -d "$UBOOT_DIR" ] && error_exit "U-Boot目录不存在: $UBOOT_DIR"
    
    # 检查大小参数是否为数字
    local sizes=("$IMG_SIZE" "$BOOT_PART_SIZE" "$ROOTFS_PART_SIZE")
    for size in "${sizes[@]}"; do
        if ! [[ "$size" =~ ^[0-9]+$ ]]; then
            error_exit "大小参数必须为数字: $size"
        fi
        if [ "$size" -lt 1 ]; then
            error_exit "大小参数必须大于0: $size"
        fi
    done
    
    # 检查分区大小合理性
    local total_part_size=$((BOOT_PART_SIZE + ROOTFS_PART_SIZE + 10)) # 增加余量用于分区表、引导等
    if [ $total_part_size -gt $IMG_SIZE ]; then
        error_exit "分区总大小 (${total_part_size}MB) 超过镜像大小 (${IMG_SIZE}MB)"
    fi
}

# 显示当前配置
show_config() {
    echo -e "${BLUE}当前配置:${NC}"
    echo -e "  内核目录: ${YELLOW}$KERNEL_DIR${NC}"
    echo -e "  U-Boot目录: ${YELLOW}$UBOOT_DIR${NC}"
    echo -e "  输出目录: ${YELLOW}$OUTPUT_DIR${NC}"
    echo -e "  镜像文件名: ${YELLOW}$IMAGE_NAME${NC}"
    echo -e "  镜像总大小: ${YELLOW}${IMG_SIZE}MB${NC}"
    echo -e "  Boot分区大小: ${YELLOW}${BOOT_PART_SIZE}MB${NC}"
    echo -e "  RootFS分区大小: ${YELLOW}${ROOTFS_PART_SIZE}MB${NC}"
    echo ""
}

# 检查必要的文件
check_files() {
    echo -e "${YELLOW}检查必要文件...${NC}"
    
    local error_count=0
    
    # 检查内核文件
    if [ ! -f "$KERNEL_DIR/out/uImage" ]; then
        echo -e "${RED}错误: 找不到 uImage 文件 ($KERNEL_DIR/out/uImage)${NC}"
        error_count=$((error_count + 1))
    else
        echo -e "${GREEN}找到 uImage 文件${NC}"
    fi
    
    # 检查设备树文件
    if [ ! -f "$KERNEL_DIR/out/sun8i-h3-quark-luoorshi.dtb" ]; then
        echo -e "${RED}错误: 找不到设备树文件 ($KERNEL_DIR/out/sun8i-h3-quark-luoorshi.dtb)${NC}"
        error_count=$((error_count + 1))
    else
        echo -e "${GREEN}找到设备树文件${NC}"
    fi
    
    # 检查U-Boot文件
    if [ ! -f "$UBOOT_DIR/u-boot-sunxi-with-spl.bin" ]; then
        echo -e "${RED}错误: 找不到 u-boot-sunxi-with-spl.bin 文件 ($UBOOT_DIR/u-boot-sunxi-with-spl.bin)${NC}"
        error_count=$((error_count + 1))
    else
        echo -e "${GREEN}找到 U-Boot 文件${NC}"
    fi
    
    if [ $error_count -gt 0 ]; then
        error_exit "发现 $error_count 个文件错误，请修复后重试"
    fi
    
    echo -e "${GREEN}所有必要文件检查通过${NC}"
    echo ""
}

# 检查所需命令
check_required_commands() {
    echo -e "${YELLOW}检查所需命令...${NC}"
    local commands=("sfdisk" "losetup" "mkfs.vfat" "mkfs.ext4" "partprobe" "mount" "umount" "dd" "mkdir")
    
    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            error_exit "所需命令 '$cmd' 未安装"
        fi
    done
    
    # 检查mkimage（可选）
    if ! command -v mkimage &> /dev/null; then
        warning_msg "mkimage 命令未找到，将跳过boot.scr生成（如果需要U-Boot脚本请安装u-boot-tools）"
    fi
    
    echo -e "${GREEN}所有命令检查完成${NC}"
}

# 创建兼容balenaEtcher的镜像
create_etcher_compatible_image() {
    local image_path="$1"
    local img_size_mb="$2"
    local boot_size_mb="$3"
    local rootfs_size_mb="$4"
    
    echo -e "${YELLOW}创建兼容balenaEtcher的镜像...${NC}"
    
    # 计算扇区数 (1MB = 2048个512字节扇区)
    local boot_sectors=$((boot_size_mb * 2048))
    local rootfs_sectors=$((rootfs_size_mb * 2048))
    local boot_start=2048  # 1MB偏移，标准对齐
    local boot_end=$((boot_start + boot_sectors - 1))
    local rootfs_start=$((boot_end + 1))
    local rootfs_end=$((rootfs_start + rootfs_sectors - 1))
    
    # 创建空白镜像文件
    safe_exec "dd if=/dev/zero of=\"$image_path\" bs=1M count=$img_size_mb status=progress" "创建空白镜像"
    
    # 使用parted创建分区表，这对balenaEtcher更友好
    echo -e "${YELLOW}创建分区表...${NC}"
    
    # 使用parted创建MBR分区表
    sudo parted -s "$image_path" mklabel msdos
    sudo parted -s "$image_path" mkpart primary fat32 ${boot_start}s ${boot_end}s
    sudo parted -s "$image_path" mkpart primary ext4 ${rootfs_start}s ${rootfs_end}s
    sudo parted -s "$image_path" set 1 boot on
    
    # 设置循环设备
    echo -e "${YELLOW}设置循环设备...${NC}"
    LOOP_DEV=$(sudo losetup -f --show -P "$image_path")
    if [ -z "$LOOP_DEV" ]; then
        error_exit "无法设置循环设备"
    fi
    CLEANUP_NEEDED=true
    
    # 等待分区设备出现
    echo -e "${YELLOW}等待分区设备就绪...${NC}"
    sleep 2
    sudo partprobe "$LOOP_DEV"
    sleep 1
    
    # 检查分区设备是否存在
    if [ ! -b "${LOOP_DEV}p1" ] || [ ! -b "${LOOP_DEV}p2" ]; then
        error_exit "分区设备未正确创建，请检查镜像大小和分区参数"
    fi
    
    # 格式化分区
    echo -e "${YELLOW}格式化分区...${NC}"
    safe_exec "sudo mkfs.vfat -F 32 -n BOOT \"${LOOP_DEV}p1\"" "格式化BOOT分区为FAT32"
    safe_exec "sudo mkfs.ext4 -L ROOTFS \"${LOOP_DEV}p2\"" "格式化ROOTFS分区为ext4"
    
    # 写入U-Boot
    echo -e "${YELLOW}写入U-Boot引导程序...${NC}"
    safe_exec "sudo dd if=\"$UBOOT_DIR/u-boot-sunxi-with-spl.bin\" of=\"$LOOP_DEV\" bs=1024 seek=8 conv=notrunc,fsync" "写入U-Boot到引导扇区"
    
    # 挂载分区
    echo -e "${YELLOW}挂载分区...${NC}"
    safe_exec "mkdir -p boot rootfs" "创建挂载点"
    safe_exec "sudo mount \"${LOOP_DEV}p1\" boot" "挂载BOOT分区"
    MOUNTED_DIRS+=("boot")
    safe_exec "sudo mount \"${LOOP_DEV}p2\" rootfs" "挂载ROOTFS分区"
    MOUNTED_DIRS+=("rootfs")
    
    # 复制内核文件
    echo -e "${YELLOW}复制内核文件到BOOT分区...${NC}"
    safe_exec "sudo cp \"$KERNEL_DIR/out/uImage\" boot/" "复制uImage"
    safe_exec "sudo cp \"$KERNEL_DIR/out/sun8i-h3-quark-luoorshi.dtb\" boot/" "复制设备树"
    
    # 创建U-Boot启动脚本（如果mkimage可用）
    if command -v mkimage &> /dev/null; then
        echo -e "${YELLOW}创建U-Boot启动脚本...${NC}"
        cat > boot.cmd << 'EOF'
# 设置内核启动参数
setenv bootargs "console=ttyS0,115200 earlyprintk root=/dev/mmcblk0p2 rootwait panic=10"
# 加载内核
load mmc 0:1 0x46000000 uImage
# 加载设备树
load mmc 0:1 0x47000000 sun8i-h3-quark-luoorshi.dtb
# 启动内核
bootm 0x46000000 - 0x47000000
EOF
        
        safe_exec "sudo mkimage -A arm -T script -C none -n \"Boot script\" -d boot.cmd boot/boot.scr" "编译boot.scr"
        rm -f boot.cmd
    else
        warning_msg "跳过boot.scr生成，mkimage命令不可用"
    fi
    
    # 创建基本的rootfs结构
    echo -e "${YELLOW}创建rootfs基本结构...${NC}"
    safe_exec "sudo mkdir -p rootfs/{bin,dev,etc,home,lib,proc,root,sbin,sys,tmp,usr,var}" "创建目录结构"
    safe_exec "sudo chmod 1777 rootfs/tmp" "设置tmp目录权限"
    
    # 创建fstab
    sudo tee rootfs/etc/fstab > /dev/null << 'EOF'
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/mmcblk0p1  /boot           vfat    defaults        0       0
/dev/mmcblk0p2  /               ext4    defaults,noatime 0       1
tmpfs           /tmp            tmpfs   defaults        0       0
EOF
    
    # 创建inittab
    sudo tee rootfs/etc/inittab > /dev/null << 'EOF'
::sysinit:/etc/init.d/rcS
::respawn:/sbin/getty -L ttyS0 115200 vt100
::restart:/sbin/init
::shutdown:/bin/umount -a -r
EOF
    
    # 创建rcS脚本
    safe_exec "sudo mkdir -p rootfs/etc/init.d" "创建init.d目录"
    sudo tee rootfs/etc/init.d/rcS > /dev/null << 'EOF'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t tmpfs tmpfs /dev
mkdir /dev/pts
mount -t devpts devpts /dev/pts
echo /sbin/mdev > /proc/sys/kernel/hotplug
mdev -s
mount -a
echo "System boot completed!"
EOF
    
    safe_exec "sudo chmod +x rootfs/etc/init.d/rcS" "设置执行权限"
    
    # 同步所有更改
    echo -e "${YELLOW}同步文件系统...${NC}"
    sync
    sleep 2
    
    # 卸载分区
    cleanup
    
    echo -e "${GREEN}镜像创建完成!${NC}"
}

# 验证镜像兼容性
verify_image_compatibility() {
    local image_path="$1"
    
    echo -e "${YELLOW}验证镜像兼容性...${NC}"
    
    # 检查文件是否存在
    if [ ! -f "$image_path" ]; then
        error_exit "镜像文件不存在: $image_path"
    fi
    
    # 检查文件大小
    local actual_size=$(du -m "$image_path" | cut -f1)
    if [ "$actual_size" -ne "$IMG_SIZE" ]; then
        warning_msg "镜像文件大小 (${actual_size}MB) 与预期大小 (${IMG_SIZE}MB) 不符"
    fi
    
    # 检查分区表
    if ! sudo fdisk -l "$image_path" &> /dev/null; then
        error_exit "镜像分区表无效"
    fi
    
    # 使用file命令检查镜像类型
    if file "$image_path" | grep -q "DOS/MBR boot sector"; then
        echo -e "${GREEN}镜像使用MBR引导扇区，兼容性良好${NC}"
    else
        warning_msg "镜像可能不是标准的MBR格式"
    fi
    
    echo -e "${GREEN}镜像验证完成${NC}"
}

# 主函数
main() {
    # 检查所需命令
    check_required_commands
    
    # 解析参数
    parse_arguments "$@"
    
    # 设置默认值
    set_defaults
    
    # 验证配置
    validate_config
    
    # 显示配置
    show_config
    
    # 检查文件
    check_files
    
    echo -e "${GREEN}开始制作TF卡镜像...${NC}"
    
    # 创建输出目录
    safe_exec "mkdir -p \"$OUTPUT_DIR\"" "创建输出目录"
    safe_exec "cd \"$OUTPUT_DIR\"" "切换到输出目录"
    
    # 检查镜像文件是否已存在
    if [ -f "$IMAGE_NAME" ]; then
        echo -e "${YELLOW}镜像文件已存在，删除旧文件...${NC}"
        rm -f "$IMAGE_NAME"
    fi
    
    local image_path="$OUTPUT_DIR/$IMAGE_NAME"
    
    # 创建镜像
    create_etcher_compatible_image "$image_path" "$IMG_SIZE" "$BOOT_PART_SIZE" "$ROOTFS_PART_SIZE"
    
    # 验证镜像
    verify_image_compatibility "$image_path"
    
    # 显示最终信息
    echo -e "\n${GREEN}=== 镜像制作完成 ===${NC}"
    echo -e "${GREEN}输出文件: $image_path${NC}"
    echo -e "${GREEN}文件大小: $(du -h "$image_path" | cut -f1)${NC}"
    echo ""
    echo -e "${YELLOW}烧录说明:${NC}"
    echo -e "  1. 使用balenaEtcher: 直接选择镜像文件烧录"
    echo -e "  2. 使用dd命令: sudo dd if=\"$image_path\" of=/dev/sdX bs=1M status=progress"
    echo -e "  3. 请将 /dev/sdX 替换为您的TF卡设备"
    echo ""
    echo -e "${YELLOW}分区信息:${NC}"
    sudo fdisk -l "$image_path" 2>/dev/null || echo "无法显示分区信息"
}

# 运行主函数
main "$@"