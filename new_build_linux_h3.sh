#!/bin/bash

# 设置严格错误处理模式
set -euo pipefail

# 配置变量，便于维护和修改
ARCH="arm"
CROSS_COMPILE="arm-linux-gnueabihf-"
DEFCONFIG="linux_card_defconfig"
JOBS=40
OUTPUT_DIR="./out"
KERNEL_VERSION="linux-5.19.6"
LOAD_ADDR="0x46000000"
ENTRY_ADDR="0x46000000"

# 颜色定义用于输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "命令 $1 未找到，请安装后重试"
        exit 1
    fi
}

# 检查必要的命令
check_command "make"
check_command "mkimage"
check_command "arm-linux-gnueabihf-gcc"

# 主编译函数
main() {
    log_info "开始内核编译过程"
    log_info "架构: $ARCH, 交叉编译工具: $CROSS_COMPILE"
    log_info "并行编译任务数: $JOBS"
    
    # 清理编译环境（可选，根据需求取消注释）
    # log_info "执行清理操作..."
    # if ! make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" clean; then
    #     log_error "清理操作失败"
    #     exit 1
    # fi
    
    # 配置内核
    log_info "配置内核: $DEFCONFIG"
    if ! make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$DEFCONFIG"; then
        log_error "内核配置失败"
        exit 1
    fi
    log_success "内核配置完成"
    
    # 编译内核
    log_info "开始编译内核，详细信息请查看编译日志..."
    if ! make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" all -j"$JOBS" V=1 2>&1 | tee build.log; then
        log_error "内核编译失败，请检查 build.log 文件获取详细错误信息"
        exit 1
    fi
    log_success "内核编译完成"
    
    # 准备输出目录
    log_info "准备输出目录: $OUTPUT_DIR"
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    # 复制编译结果
    log_info "复制内核镜像文件..."
    if [ ! -f "arch/arm/boot/zImage" ]; then
        log_error "zImage 文件未找到，编译可能未成功生成内核镜像"
        exit 1
    fi
    
    if [ ! -f "arch/arm/boot/dts/sun8i-h3-quark-luoorshi.dtb" ]; then
        log_error "设备树文件未找到"
        exit 1
    fi
    
    cp arch/arm/boot/zImage "$OUTPUT_DIR/"
    cp arch/arm/boot/dts/sun8i-h3-quark-luoorshi.dtb "$OUTPUT_DIR/"
    log_success "文件复制完成"
    
    # 生成 uImage
    log_info "生成 uImage..."
    cd "$OUTPUT_DIR"
    if ! mkimage -A arm -O linux -T kernel -C none -a "$LOAD_ADDR" -e "$ENTRY_ADDR" -n "$KERNEL_VERSION" -d zImage uImage; then
        log_error "uImage 生成失败"
        exit 1
    fi
    cd ..
    log_success "uImage 生成完成"
    
    # 显示编译结果
    log_success "编译过程全部完成！"
    log_info "生成的文件:"
    ls -la "$OUTPUT_DIR/"
    echo
    log_info "输出目录: $OUTPUT_DIR"
    log_info "内核镜像: $OUTPUT_DIR/uImage"
    log_info "设备树文件: $OUTPUT_DIR/sun8i-h3-quark-luoorshi.dtb"
}

# 执行时间统计
start_time=$(date +%s)

# 运行主函数
main

end_time=$(date +%s)
execution_time=$((end_time - start_time))

log_success "总编译时间: ${execution_time} 秒"

# 可选：生成编译报告
echo "=== 编译报告 ===" > "$OUTPUT_DIR/build_report.txt"
echo "编译时间: $(date)" >> "$OUTPUT_DIR/build_report.txt"
echo "架构: $ARCH" >> "$OUTPUT_DIR/build_report.txt"
echo "交叉编译工具: $CROSS_COMPILE" >> "$OUTPUT_DIR/build_report.txt"
echo "配置: $DEFCONFIG" >> "$OUTPUT_DIR/build_report.txt"
echo "编译耗时: ${execution_time} 秒" >> "$OUTPUT_DIR/build_report.txt"
echo "生成文件:" >> "$OUTPUT_DIR/build_report.txt"
ls -1 "$OUTPUT_DIR/" >> "$OUTPUT_DIR/build_report.txt"

log_info "详细编译报告已保存至: $OUTPUT_DIR/build_report.txt"