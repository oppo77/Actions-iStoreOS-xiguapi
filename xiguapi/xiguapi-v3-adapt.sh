#!/bin/bash
set -euo pipefail  # 严格模式，出错立即退出

# ===================== 核心路径配置（基于脚本自身目录） =====================
# 获取脚本所在目录（绝对路径）
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# 设备文件源目录 = 脚本所在目录（dts/defconfig/dtsi 与脚本同目录）
DEVICE_FILES_DIR="${SCRIPT_DIR}"
# 源码根目录 = 脚本目录的上级目录（假设 xiguapi-v3/ 放在 OpenWrt/iStoreOS 源码根目录下）
SOURCE_ROOT_DIR=$(cd "${SCRIPT_DIR}/../openwrt" && pwd)

# ===================== 设备固定配置 =====================
DEVICE_NAME="xiguapi-v3"
SOC="rk3568"
DEVICE_DEF="nlnet_xiguapi-v3"
UBOOT_CONFIG="rk3568-xiguapi-v3"

# ===================== 工具函数 =====================
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

warn() {
    echo -e "\033[33m[WARN] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    exit 1
}

# 检查目录是否存在，不存在则创建
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error "创建目录失败: $dir"
        info "创建目录: $dir"
    fi
}

# 复制文件并备份原文件
copy_file_with_backup() {
    local src="$1"
    local dest="$2"
    ensure_dir "$(dirname "$dest")"
    
    if [ -f "$src" ]; then
        # 备份目标文件（仅第一次）
        if [ -f "$dest" ] && [ ! -f "${dest}.bak.xiguapi" ]; then
            cp -f "$dest" "${dest}.bak.xiguapi"
            info "备份原文件: ${dest}.bak.xiguapi"
        fi
        cp -f "$src" "$dest"
        info "复制文件: $src -> $dest"
    else
        error "源文件不存在: $src"
    fi
}

# ===================== 核心操作函数 =====================

# 1. 初始化检查
init_check() {
    info "===== 1. 初始化检查 ====="
    # 验证脚本目录和设备文件
    info "脚本所在目录: ${SCRIPT_DIR}"
    info "源码根目录: ${SOURCE_ROOT_DIR}"

    # 检查关键设备文件是否存在
    local required_files=(
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi"
    )
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "必需的设备文件不存在: $file"
        fi
    done
    info "所有必需的设备文件已找到"

    # 切换到源码根目录（核心：所有操作基于源码根目录）
    cd "${SOURCE_ROOT_DIR}" || error "切换到源码根目录失败: ${SOURCE_ROOT_DIR}"
    info "当前工作目录（源码根）: $(pwd)"
}

# 2. 复制DTS/defconfig/dtsi文件
copy_device_files() {
    info "===== 2. 复制设备相关文件 ====="
    
    # 2.1 target/linux/rockchip/dts/rk3568 添加dts
    local dts_dest="target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$dts_dest"

    # 2.2 package/boot/uboot-rockchip/src/configs 添加defconfig
    local defconfig_dest="package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig" "$defconfig_dest"

    # 2.3 package/boot/uboot-rockchip/src/arch/arm/dts 添加dtsi
    local dtsi_dest="package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "$dtsi_dest"

    # 2.4 package/boot/uboot-rockchip/src/dts/upstream/src/arm64/rockchip 添加dts
    local upstream_dts_dest="package/boot/uboot-rockchip/src/dts/upstream/src/arm64/rockchip/rk3568-xiguapi-v3.dts"
    copy_file_with_backup "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$upstream_dts_dest"
}

# 3. 修改target/linux/rockchip/image/armv8.mk（添加设备定义）
modify_armv8_mk() {
    info "===== 3. 修改armv8.mk（添加设备定义） ====="
    local armv8_mk="target/linux/rockchip/image/armv8.mk"
    
    # 备份原文件
    if [ ! -f "${armv8_mk}.bak.xiguapi" ]; then
        cp -f "$armv8_mk" "${armv8_mk}.bak.xiguapi"
        info "备份原armv8.mk: ${armv8_mk}.bak.xiguapi"
    fi

    # 检查是否已存在设备定义，避免重复添加
    if grep -q "define Device/${DEVICE_DEF}" "$armv8_mk"; then
        warn "设备定义 ${DEVICE_DEF} 已存在，跳过添加"
        return
    fi

    # 添加设备定义到文件末尾
    cat >> "$armv8_mk" << EOF

# Added for Xiguapi V3 (rk3568)
define Device/${DEVICE_DEF}
  DEVICE_VENDOR := NLNET
  DEVICE_MODEL := Xiguapi V3
  SOC := ${SOC}
  DEVICE_DTS_DIR := ../dts/${SOC}
  DEVICE_DTS := ${UBOOT_CONFIG}
  UBOOT_DEVICE_NAME := ${UBOOT_CONFIG}
  KERNEL_LOADADDR := 0x04000000
  BOOT_SCRIPT := rockchip
  DEVICE_PACKAGES := kmod-r8169
endef
TARGET_DEVICES += ${DEVICE_DEF}
EOF
    info "已添加 ${DEVICE_DEF} 设备定义到 armv8.mk"
}

# 4. 修改package/boot/uboot-rockchip/Makefile
modify_uboot_makefile() {
    info "===== 4. 修改uboot-rockchip Makefile ====="
    local uboot_makefile="package/boot/uboot-rockchip/Makefile"
    
    # 备份原文件
    if [ ! -f "${uboot_makefile}.bak.xiguapi" ]; then
        cp -f "$uboot_makefile" "${uboot_makefile}.bak.xiguapi"
        info "备份原uboot Makefile: ${uboot_makefile}.bak.xiguapi"
    fi

    # 4.1 添加U-Boot/xiguapi-v3-rk3568定义
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"
    if grep -q "$uboot_def" "$uboot_makefile"; then
        warn "U-Boot定义 ${uboot_def} 已存在，跳过添加"
    else
        # 在文件末尾添加U-Boot定义
        cat >> "$uboot_makefile" << EOF

# Added for Xiguapi V3 (rk3568)
define ${uboot_def}
  \$(U-Boot/${SOC}/Default)
  NAME:=Xiguapi V3
  UBOOT_CONFIG:=${UBOOT_CONFIG}
  BUILD_DEVICES:= \
    ${DEVICE_DEF}
endef
EOF
        info "已添加 ${uboot_def} 定义到uboot Makefile"
    fi

    # 4.2 在UBOOT_TARGETS列表中添加xiguapi-v3-rk3568
    if grep -q " ${DEVICE_NAME}-${SOC} " "$uboot_makefile"; then
        warn "UBOOT_TARGETS 中已包含 ${DEVICE_NAME}-${SOC}，跳过添加"
    else
        # 兼容单行/多行UBOOT_TARGETS格式
        sed -i "/^UBOOT_TARGETS :=/ {
            /\\\$/! s/$/ \\\\/
            a \ \ ${DEVICE_NAME}-${SOC} \\
        }" "$uboot_makefile"
        # 清理最后一行多余的反斜杠
        sed -i "/^UBOOT_TARGETS :=/ {
            :loop
            n
            /^[^ \t]/! {
                s/\\\$//
                b loop
            }
        }" "$uboot_makefile"
        info "已在UBOOT_TARGETS中添加 ${DEVICE_NAME}-${SOC}"
    fi
}

# 5. 修改iStoreOS/OpenWrt设备配置文件
modify_device_configs() {
    info "===== 5. 修改设备配置文件（LED/网络/初始化） ====="
    
    # 5.1 修改01_leds（LED配置）
    local leds_file="target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    ensure_dir "$(dirname "$leds_file")"
    [ ! -f "$leds_file" ] && touch "$leds_file" && info "创建空文件: $leds_file"
    [ ! -f "${leds_file}.bak.xiguapi" ] && cp -f "$leds_file" "${leds_file}.bak.xiguapi"

    if ! grep -q "nlnet,${DEVICE_NAME}" "$leds_file"; then
        sed -i '/^case \$board in/,/^esac/ {
            /^esac/i\
nlnet,${DEVICE_NAME})\
    ucidef_set_led_default "power" "POWER" "blue:power" "1"\
    ucidef_set_led_netdev "status" "STATUS" "blue:status" "eth0"\
    ucidef_set_led_netdev "network" "NETWORK" "blue:network" "eth1"\
    ;;
        }' "$leds_file"
        info "已添加 ${DEVICE_NAME} LED配置到 01_leds"
    else
        warn "${DEVICE_NAME} LED配置已存在，跳过"
    fi

    # 5.2 修改02_network（网络接口/MAC）
    local network_file="target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
    ensure_dir "$(dirname "$network_file")"
    [ ! -f "$network_file" ] && touch "$network_file" && info "创建空文件: $network_file"
    [ ! -f "${network_file}.bak.xiguapi" ] && cp -f "$network_file" "${network_file}.bak.xiguapi"

    if ! grep -q "nlnet,${DEVICE_NAME}" "$network_file"; then
        # 网络接口配置
        sed -i '/rockchip_setup_interfaces()/,/^}/ {
            /^\s*\*)/i\
\tnlnet,${DEVICE_NAME})\
\t\tucidef_set_interfaces_lan_wan "eth0" "eth1"\
\t\t;;
        }' "$network_file"
        # MAC地址配置
        sed -i '/rockchip_setup_macs()/,/^}/ {
            /^\s*\*)/i\
\tnlnet,${DEVICE_NAME})\
\t\twan_mac=\$(generate_mac_from_boot_mmc)\
\t\tlan_mac=\$(macaddr_add "\$wan_mac" 1)\
\t\t;;
        }' "$network_file"
        info "已添加 ${DEVICE_NAME} 网络/MAC配置到 02_network"
    else
        warn "${DEVICE_NAME} 网络配置已存在，跳过"
    fi

    # 5.3 修改init.sh（接口修复/SMP亲和性）
    local init_file="target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    ensure_dir "$(dirname "$init_file")"
    [ ! -f "$init_file" ] && touch "$init_file" && info "创建空文件: $init_file"
    [ ! -f "${init_file}.bak.xiguapi" ] && cp -f "$init_file" "${init_file}.bak.xiguapi"

    if ! grep -q "nlnet,${DEVICE_NAME}" "$init_file"; then
        # 接口修复
        sed -i '/board_fixup_iface_name()/,/^}/ {
            /^\s*\*)/i\
\tnlnet,${DEVICE_NAME})\
\t\t# No interface renaming needed\
\t\t;;
        }' "$init_file"
        # SMP亲和性
        sed -i '/board_set_iface_smp_affinity()/,/^}/ {
            /^\s*\*)/i\
\tnlnet,${DEVICE_NAME})\
\t\tset_iface_cpumask 2 eth0\
\t\tset_iface_cpumask 4 eth1\
\t\t;;
        }' "$init_file"
        info "已添加 ${DEVICE_NAME} 初始化配置到 init.sh"
    else
        warn "${DEVICE_NAME} init.sh配置已存在，跳过"
    fi
}

# 6. 验证所有修改
verify_changes() {
    info "===== 6. 验证修改结果 ====="
    local error_count=0

    # 验证设备定义
    if ! grep -q "${DEVICE_DEF}" "target/linux/rockchip/image/armv8.mk"; then
        error "验证失败: armv8.mk中未找到 ${DEVICE_DEF} 设备定义"
        error_count=$((error_count+1))
    else
        info "✓ armv8.mk 设备定义验证通过"
    fi

    # 验证UBOOT定义
    if ! grep -q "${DEVICE_NAME}-${SOC}" "package/boot/uboot-rockchip/Makefile"; then
        warn "验证警告: uboot Makefile中未找到 ${DEVICE_NAME}-${SOC} 定义"
        error_count=$((error_count+1))
    else
        info "✓ uboot Makefile 定义验证通过"
    fi

    # 验证DTS文件
    if [ ! -f "target/linux/rockchip/dts/rk3568/${UBOOT_CONFIG}.dts" ]; then
        error "验证失败: DTS文件不存在"
        error_count=$((error_count+1))
    else
        info "✓ DTS文件验证通过"
    fi

    # 验证LED/网络/init配置
    local check_files=(
        "target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
        "target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
        "target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    )
    for file in "${check_files[@]}"; do
        if ! grep -q "nlnet,${DEVICE_NAME}" "$file"; then
            warn "验证警告: $file 中未找到 ${DEVICE_NAME} 配置"
            error_count=$((error_count+1))
        else
            info "✓ $file 配置验证通过"
        fi
    done

    if [ $error_count -gt 0 ]; then
        error "共发现 ${error_count} 个验证错误，适配失败"
    else
        info "✓ 所有修改验证通过！"
    fi
}

# ===================== 主流程 =====================
main() {
    info "===== 开始Xiguapi V3 (rk3568) 固件适配 ====="
    init_check
    copy_device_files
    modify_armv8_mk
    modify_uboot_makefile
    modify_device_configs
    verify_changes
    info "===== Xiguapi V3 固件适配完成 ====="
}

# 执行主流程
main

exit 0
