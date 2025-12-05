#!/bin/bash
set -euo pipefail

# ===================== 核心配置（锚定OpenWRT根目录）=====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEVICE_FILES_DIR="${SCRIPT_DIR}"
OPENWRT_ROOT="${OPENWRT_ROOT:-${SCRIPT_DIR}/../workdir/openwrt}"

# 切换到OpenWRT根目录（GitHub Action环境路径需准确）
cd "$OPENWRT_ROOT" || { echo -e "\033[31m[ERROR] 未找到OpenWRT源码目录：${OPENWRT_ROOT}\033[0m"; exit 1; }
SOURCE_ROOT_DIR=$(pwd)

# 设备核心配置
DEVICE_NAME="xiguapi-v3"
SOC="rk3568"
DEVICE_DEF="nlnet_xiguapi-v3"
UBOOT_CONFIG="rk3568-xiguapi-v3"
BOARD_FULL_NAME="nlnet,${DEVICE_NAME}"
TARGET_DEVICE="${DEVICE_NAME}-${SOC}"

# ===================== 工具函数（极简版，适配GitHub Action）=====================
info() { echo -e "\033[32m[INFO] $1\033[0m"; }
warn() { echo -e "\033[33m[WARN] $1\033[0m"; }
error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    [ -f "package/boot/uboot-rockchip/Makefile" ] && grep -A10 -B10 "UBOOT_TARGETS" "package/boot/uboot-rockchip/Makefile" || true
    exit 1
}

# 仅复制文件（不创建目录/备份，GitHub Action环境需提前准备目录）
copy_file() {
    local src="$1" dest="$2"
    [ -f "$src" ] || error "源文件不存在: $src"
    cp -f "$src" "$dest" || error "复制失败: $src → $dest"
    info "复制文件: $src → $dest"
}

# ===================== 核心逻辑（整合所有修复点）=====================
init_check() {
    info "===== 1. 初始化检查 ====="
    local required_files=(
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi"
    )
    # 检查必需设备文件
    for file in "${required_files[@]}"; do
        [ -f "$file" ] || error "必需文件缺失: $file"
    done
    info "所有必需设备文件验证通过"

    # 检查核心依赖文件
    local core_files=(
        "package/boot/uboot-rockchip/Makefile"
        "target/linux/rockchip/image/armv8.mk"
        "target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
        "target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
        "target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    )
    for file in "${core_files[@]}"; do
        [ -f "$file" ] || error "核心文件缺失: $file"
    done
    info "所有核心依赖文件验证通过"

    # 检查U-Boot rk3568基础定义
    grep -q "define U-Boot/rk3568/Default" "package/boot/uboot-rockchip/Makefile" || error "U-Boot rk3568基础定义缺失"
}

copy_device_files() {
    info "===== 2. 复制设备文件 ====="
    # DTS文件（target/linux/rockchip/dts/rk3568/需提前存在）
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
    # U-Boot defconfig（package/boot/uboot-rockchip/src/configs/需提前存在）
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig" "package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig"
    # U-Boot dtsi（package/boot/uboot-rockchip/src/arch/arm/dts/需提前存在）
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
}

modify_armv8_mk() {
    info "===== 3. 修改armv8.mk（插入到正确位置） ====="
    local armv8_mk="target/linux/rockchip/image/armv8.mk"
    local device_tag="nlnet_xiguapi-v3"
    local device_comment="# Added for Xiguapi V3 (rk3568)"
    # 定义要插入的内容（无开头空行，变量可维护）
    local insert_content="
${device_comment}
define Device/${device_tag}
  DEVICE_VENDOR := NLNET
  DEVICE_MODEL := Xiguapi V3
  SOC := rk3568
  DEVICE_DTS_DIR := ../dts/rk3568
  DEVICE_DTS := rk3568-xiguapi-v3
  UBOOT_DEVICE_NAME := rk3568-xiguapi-v3
  KERNEL_LOADADDR := 0x04000000
  BOOT_SCRIPT := rockchip
  DEVICE_PACKAGES := kmod-r8169
endef
TARGET_DEVICES += ${device_tag}"

    # 前置检查：文件是否存在且可写
    if [ ! -f "$armv8_mk" ]; then
        error "错误：${armv8_mk} 文件不存在！"
        return 1
    fi
    if [ ! -w "$armv8_mk" ]; then
        error "错误：${armv8_mk} 无写入权限！"
        return 1
    fi

    # 前置检查：是否存在include legacy.mk行
    if ! grep -q "^include legacy\.mk$" "$armv8_mk"; then
        error "错误：${armv8_mk} 中未找到 'include legacy.mk' 行，无法插入配置！"
        return 1
    fi

    # 第一步：删除原有配置（兼容行首空格，避免重复）
    sed -i.bak '/^[[:space:]]*'"${device_comment}"'/,$ {
        /^[[:space:]]*TARGET_DEVICES += '"${device_tag}"'/ {
            d; b end
        }
        d
        :end
    }' "$armv8_mk"
    # 删除sed生成的备份文件（跨平台兼容）
    rm -f "${armv8_mk}.bak"

    # 第二步：安全插入配置（用sed替代awk，解决多行传递问题）
    # 适配Linux/BSD/macOS的sed语法
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS/BSD sed
        sed -i '' "/^include legacy\.mk$/i\\
${insert_content}" "$armv8_mk"
    else
        # Linux sed
        sed -i "/^include legacy\.mk$/i ${insert_content}" "$armv8_mk"
    fi

    # 第三步：验证插入结果（正确逻辑）
    # 逻辑：1. 存在设备配置；2. include legacy.mk在配置之后
    if grep -q "${device_tag}" "$armv8_mk" && 
       grep -B100 "include legacy\.mk" "$armv8_mk" | grep -q "${device_tag}"; then
        info "✓ ${device_tag} 已插入到armv8.mk正确位置（include legacy.mk之前）"
    else
        error "armv8.mk配置插入失败！请手动检查文件：${armv8_mk}"
        return 1
    fi

    return 0
}

modify_uboot_makefile() {
    info "===== 4. 修改uboot-rockchip Makefile ====="
    local uboot_make="package/boot/uboot-rockchip/Makefile"

    # 第一步：删除原有Xiguapi V3定义（避免重复）
    sed -i '/^# Added for Xiguapi V3 (rk3568)/,/^endef/d' "$uboot_make"
    
    # 第二步：添加正确的U-Boot设备定义（修复BUILD_DEVICES语法）
    cat >> "$uboot_make" <<-EOF

# Added for Xiguapi V3 (rk3568)
define U-Boot/${TARGET_DEVICE}
	\$(U-Boot/rk3568/Default)
	NAME:=Xiguapi V3
	BUILD_DEVICES := \\
		nlnet_xiguapi-v3
endef
EOF

    # 第三步：修复UBOOT_TARGETS（简洁sed，确保添加成功）
    # 先删除旧目标避免重复
    sed -i "/UBOOT_TARGETS/ s/ ${TARGET_DEVICE}//g" "$uboot_make"
    # 追加新目标（兼容单行/多行格式）
    if grep -q "^UBOOT_TARGETS :=" "$uboot_make"; then
        sed -i "/UBOOT_TARGETS/ {
            :a
            N
            /\\$/!ba
            s/\\$/ \\\n  ${TARGET_DEVICE}/
        }" "$uboot_make"
    else
        echo -e "\nUBOOT_TARGETS := \\\n  ${TARGET_DEVICE}" >> "$uboot_make"
    fi

    # 验证结果
    if grep -q "\b${TARGET_DEVICE}\b" "$uboot_make"; then
        info "✓ ${TARGET_DEVICE} 已添加到 UBOOT_TARGETS"
    else
        error "UBOOT_TARGETS 写入失败！"
    fi
}

modify_device_configs() {
    info "===== 5. 修改设备配置文件 ====="
    local escaped_board="${BOARD_FULL_NAME//,/\\,}"

    # 5.1 修改01_leds（LED配置）
    local leds_file="target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    # 删除旧配置
    sed -i "/${escaped_board})/,/^[[:space:]]*;;/d" "$leds_file"
    # 插入新配置
    sed -i '/^case \$board in/,/^esac/ {
        /^esac/i\
${escaped_board})\
\tucidef_set_led_default "power" "POWER" "blue:power" "1"\
\tucidef_set_led_netdev "status" "STATUS" "blue:status" "eth0"\
\tucidef_set_led_netdev "network" "NETWORK" "blue:network" "eth1"\
\t;;
    }' "$leds_file"
    info "✓ LED配置已添加到 01_leds"

    # 5.2 修改02_network（网络+MAC配置）
    local network_file="target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
    # 删除旧配置
    sed -i "/${escaped_board})/,/^[[:space:]]*;;/d" "$network_file"
    # 插入网络接口配置
    sed -i '/rockchip_setup_interfaces()/,/^}/ {
        /^\s*\*)/i\
\tnlnet,xiguapi-v3)\
\t\tucidef_set_interfaces_lan_wan "eth0" "eth1"\
\t\t;;
    }' "$network_file"
    # 插入MAC地址配置
    sed -i '/rockchip_setup_macs()/,/^}/ {
        /^\s*\*)/i\
\tnlnet,xiguapi-v3)\
\t\twan_mac=\$(generate_mac_from_boot_mmc)\
\t\tlan_mac=\$(macaddr_add "\$wan_mac" 1)\
\t\t;;
    }' "$network_file"
    info "✓ 网络+MAC配置已添加到 02_network"

    # 5.3 修改init.sh（接口修复+SMP亲和性）
    local init_file="target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    # 删除旧配置
    sed -i "/${escaped_board})/,/^[[:space:]]*;;/d" "$init_file"
    # 插入接口名称修复
    sed -i '/board_fixup_iface_name()/,/^}/ {
        /^\s*\*)/i\
\tnlnet,xiguapi-v3)\
\t\t# No interface renaming needed\
\t\t;;
    }' "$init_file"
    # 插入SMP亲和性配置
    sed -i '/board_set_iface_smp_affinity()/,/^}/ {
        /^\s*\*)/i\
\tnlnet,xiguapi-v3)\
\t\tset_iface_cpumask 2 eth0\
\t\tset_iface_cpumask 4 eth1\
\t\t;;
    }' "$init_file"
    info "✓ 初始化配置已添加到 init.sh"
}

verify_changes() {
    info "===== 6. 验证所有修改结果 ====="
    local error_count=0

    # 1. 验证armv8.mk配置
    if ! grep -q "define Device/${DEVICE_DEF}" "target/linux/rockchip/image/armv8.mk"; then
        warn "armv8.mk 无 ${DEVICE_DEF} 设备定义"
        error_count=$((error_count+1))
    else
        info "✓ armv8.mk 设备定义验证通过"
    fi


    # 4. 验证设备文件复制
    local device_files=(
        "target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
        "package/boot/uboot-rockchip/src/configs/rk3568-xiguapi-v3_defconfig"
        "package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    )
    for file in "${device_files[@]}"; do
        if [ ! -f "$file" ] || [ ! -s "$file" ]; then
            warn "设备文件缺失/为空: $file"
            error_count=$((error_count+1))
        fi
    done
    [ $error_count -eq 0 ] && info "✓ 所有设备文件复制验证通过"

    # 5. 验证DTS设备标识
    if grep -q "xiguapi-v3" "target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"; then
        info "✓ DTS文件包含设备标识"
    else
        warn "DTS文件无设备标识"
        error_count=$((error_count+1))
    fi

    # 6. 验证配置文件（LED/网络/初始化）
    local config_checks=(
        "01_leds:${BOARD_FULL_NAME}"
        "02_network:${BOARD_FULL_NAME}"
        "init.sh:${BOARD_FULL_NAME}"
    )
    for check in "${config_checks[@]}"; do
        local file="${check%%:*}" content="${check#:*}"
        local path="target/linux/rockchip/armv8/base-files/etc/board.d/$file"
        [ "$file" = "init.sh" ] && path="target/linux/rockchip/armv8/base-files/lib/board/$file"
        if ! grep -q "$content" "$path"; then
            warn "$file 无 $content 配置"
            error_count=$((error_count+1))
        else
            info "✓ $file 配置验证通过"
        fi
    done

    # 7. 验证mkimage工具（仅警告）
    command -v mkimage &>/dev/null || warn "mkimage 未安装（可能影响U-Boot编译）"

    # 最终结果判断
    if [ $error_count -gt 0 ]; then
        error "共发现 ${error_count} 个验证错误，适配失败"
    else
        info "✅ 所有修改验证通过！Xiguapi V3 (rk3568) 固件适配成功"
    fi
}

# ===================== 主流程（适配GitHub Action）=====================
main() {
    info "===== 开始Xiguapi V3 (rk3568) 固件适配流程 ====="
    init_check
    copy_device_files
    modify_armv8_mk
    modify_uboot_makefile
    modify_device_configs
    verify_changes
    info "===== 适配流程完成！可开始编译固件 ====="
}

main
exit 0
