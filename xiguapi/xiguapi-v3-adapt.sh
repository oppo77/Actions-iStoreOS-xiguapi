#!/bin/bash
set -euo pipefail  # 严格模式，出错立即退出

# ===================== 核心路径配置 =====================
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEVICE_FILES_DIR="${SCRIPT_DIR}"

# 优先读取环境变量，默认指向脚本上级的openwrt目录
OPENWRT_ROOT="${OPENWRT_ROOT:-${SCRIPT_DIR}/../openwrt}"
SOURCE_ROOT_DIR=$(cd "${OPENWRT_ROOT}" && pwd) || { 
    echo "ERROR: 未找到OpenWRT源码目录！请检查："
    echo "  1. 是否克隆了OpenWRT源码到 ${SCRIPT_DIR}/../openwrt 目录；"
    echo "  2. 或通过 export OPENWRT_ROOT=「你的源码目录」 指定路径；"
    exit 1; 
}

# ===================== 设备固定配置 =====================
DEVICE_NAME="xiguapi-v3"
SOC="rk3568"
DEVICE_DEF="nlnet_xiguapi-v3"
UBOOT_CONFIG="rk3568-xiguapi-v3"  # 仅用于DTS命名
BOARD_FULL_NAME="nlnet,${DEVICE_NAME}"
NETWORK_DRIVER="kmod-r8169"

# ===================== 工具函数 =====================
info() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

warn() {
    echo -e "\033[33m[WARN] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    # 调试：输出关键文件内容
    if [ -f "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds" ]; then
        echo -e "\033[31m[DEBUG] 01_leds 文件内容片段：\033[0m"
        grep -A10 -B2 "${BOARD_FULL_NAME//,/\\,}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds" || true
    fi
    # 新增：调试输出uboot Makefile关键内容
    if [ -f "${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile" ]; then
        echo -e "\033[31m[DEBUG] uboot-rockchip Makefile 片段：\033[0m"
        grep -A10 -B2 "${DEVICE_NAME}-${SOC}" "${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile" || true
        echo -e "\033[31m[DEBUG] UBOOT_TARGETS 行：\033[0m"
        grep "^[[:space:]]*UBOOT_TARGETS" "${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile" || true
    fi
    exit 1
}

ensure_dir() {
    local dir="$1"
    [ -d "$dir" ] || mkdir -p "$dir" || error "创建目录失败: $dir"
}

copy_file() {
    local src="$1"
    local dest="$2"
    ensure_dir "$(dirname "$dest")"
    
    [ -f "$src" ] || error "源文件不存在: $src"
    cp -f "$src" "$dest" || error "复制文件失败: $src -> $dest"
    info "复制文件: $src -> $dest"
}

# ===================== 核心操作函数 =====================
init_check() {
    info "===== 1. 初始化检查 ====="
    local required_files=(
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi"
    )
    for file in "${required_files[@]}"; do
        [ -f "$file" ] || error "必需设备文件缺失: $file"
    done
    info "所有必需设备文件验证通过"

    local uboot_default_def="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    grep -q "define U-Boot/rk3568/Default" "$uboot_default_def" || error "U-Boot核心依赖缺失：未找到 U-Boot/rk3568/Default"
    info "U-Boot rk3568 Default 依赖验证通过"

    cd "${SOURCE_ROOT_DIR}" || error "无法进入源码根目录: ${SOURCE_ROOT_DIR}"
    [ -x "${BASH_SOURCE[0]}" ] || chmod +x "${BASH_SOURCE[0]}" && warn "脚本无执行权限，已自动添加"
}

copy_device_files() {
    info "===== 2. 复制设备文件 ====="
    local dts_dest="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"

    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$dts_dest"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig" "$defconfig_dest"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "$dtsi_dest"

    # 验证复制结果
    local uboot_copy_files=("$defconfig_dest" "$dtsi_dest")
    for file in "${uboot_copy_files[@]}"; do
        [ -f "$file" ] && [ -s "$file" ] || error "U-Boot文件复制失败：$file 不存在/为空"
        info "✓ U-Boot文件验证通过: $file"
    done
}

modify_armv8_mk() {
    info "===== 3. 修改armv8.mk ====="
    local armv8_mk="${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"
    grep -q "define Device/${DEVICE_DEF}" "$armv8_mk" && { warn "${DEVICE_DEF} 已存在于 armv8.mk，跳过"; return; }

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
  DEVICE_PACKAGES := ${NETWORK_DRIVER}
endef
TARGET_DEVICES += ${DEVICE_DEF}
EOF
    info "已添加 ${DEVICE_DEF} 到 armv8.mk"
}

modify_uboot_makefile() {
    info "===== 4. 修改uboot-rockchip Makefile ====="
    local uboot_makefile="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"
    local target_device="${DEVICE_NAME}-${SOC}"

    # 1. 添加U-Boot定义（强制Tab缩进BUILD_DEVICES）
    if ! grep -q "$uboot_def" "$uboot_makefile"; then
        # 使用printf确保Tab缩进（\t）
        printf "\n# Added for Xiguapi V3 (rk3568)\ndefine %s\n\t\$(U-Boot/rk3568/Default)\n\tNAME:=Xiguapi V3\n\tBUILD_DEVICES := \\\\\n\t\t%s\nendef\n" "$uboot_def" "$DEVICE_DEF" >> "$uboot_makefile"
        info "已添加 ${uboot_def} 定义（Tab缩进确保语法正确）"
    else
        warn "${uboot_def} 已存在，跳过"
    fi

    # 2. 修复UBOOT_TARGETS添加（改用更可靠的方式）
    if ! grep -q "\\b${target_device}\\b" "$uboot_makefile"; then
        # 方法1：如果UBOOT_TARGETS行存在，追加；否则新增
        if grep -q "^[[:space:]]*UBOOT_TARGETS" "$uboot_makefile"; then
            sed -i "/^[[:space:]]*UBOOT_TARGETS[[:space:]]*:=/ s/\$/ ${target_device}/" "$uboot_makefile"
        else
            echo -e "\nUBOOT_TARGETS += ${target_device}" >> "$uboot_makefile"
        fi
        info "已添加 ${target_device} 到 UBOOT_TARGETS"
    else
        warn "${target_device} 已在UBOOT_TARGETS中，跳过"
    fi

    # 验证添加结果
    grep -q "\\b${target_device}\\b" "$uboot_makefile" || error "UBOOT_TARGETS 添加失败！"
}

modify_device_configs() {
    info "===== 5. 修改设备配置文件 ====="
    
    # 5.1 修复01_leds（你的文件已正确，保留逻辑）
    local leds_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    [ -f "$leds_file" ] || error "LED配置文件不存在: $leds_file"
    if ! grep -q "${BOARD_FULL_NAME//,/\\,}" "$leds_file"; then
        # 在esac前插入（适配你的文件格式）
        sed -i "/^esac$/i\\${BOARD_FULL_NAME})\\
\tucidef_set_led_default \"power\" \"POWER\" \"blue:power\" \"1\"\\
\tucidef_set_led_netdev \"status\" \"STATUS\" \"blue:status\" \"eth0\"\\
\tucidef_set_led_netdev \"network\" \"NETWORK\" \"blue:network\" \"eth1\"\\
\t;;" "$leds_file"
        info "已添加 ${DEVICE_NAME} LED配置"
    else
        warn "${DEVICE_NAME} LED配置已存在，跳过"
    fi

    # 5.2 修复02_network（适配你的多行|\格式的case）
    local network_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
    [ -f "$network_file" ] || error "网络配置文件不存在: $network_file"
    if ! grep -q "${BOARD_FULL_NAME//,/\\,}" "$network_file"; then
        # 插入到rockchip_setup_interfaces的*)前（适配你的case格式）
        sed -i "/^\\t\\*)\\$/i\\t${BOARD_FULL_NAME})\\
\\t\\ Tucidef_set_interfaces_lan_wan \"eth0\" \"eth1\"\\
\\t\\ ;;" "$network_file"
        # 插入到rockchip_setup_macs的*)前
        sed -i "/^\\t\\*)\\$/i\\t${BOARD_FULL_NAME})\\
\\t\\ wan_mac=\$(generate_mac_from_boot_mmc)\\
\\t\\ lan_mac=\$(macaddr_add \"\$wan_mac\" 1)\\
\\t\\ ;;" "$network_file"
        info "已添加 ${DEVICE_NAME} 网络配置"
    else
        warn "${DEVICE_NAME} 网络配置已存在，跳过"
    fi

    # 5.3 修复init.sh（适配你的函数格式）
    local init_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    [ -f "$init_file" ] || error "初始化配置文件不存在: $init_file"
    if ! grep -q "${BOARD_FULL_NAME//,/\\,}" "$init_file"; then
        # 插入到board_fixup_iface_name的*)前
        sed -i "/^\\t\\*)\\$/i\\t${BOARD_FULL_NAME})\\
\\t\\ # No interface renaming needed\\
\\t\\ ;;" "$init_file"
        # 插入到board_set_iface_smp_affinity的*)前
        sed -i "/^board_set_iface_smp_affinity() {/,/^\\t\\*)\\$/ s/^\\t\\*)\\$/\\t${BOARD_FULL_NAME})\\
\\t\\ set_iface_cpumask 2 eth0\\
\\t\\ set_iface_cpumask 4 eth1\\
\\t\\ ;;\n\\t\\*)/" "$init_file"
        info "已添加 ${DEVICE_NAME} 初始化配置"
    else
        warn "${DEVICE_NAME} 初始化配置已存在，跳过"
    fi
}

verify_changes() {
    info "===== 6. 验证修改结果 ====="
    local error_count=0
    local dts_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/${UBOOT_CONFIG}.dts"
    local uboot_makefile="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"
    local escaped_board_name="${BOARD_FULL_NAME//,/\\,}"

    # 验证armv8.mk
    if ! grep -q "define Device/${DEVICE_DEF}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"; then
        warn "armv8.mk 中未找到 ${DEVICE_DEF} 设备定义"
        error_count=$((error_count+1))
    else
        info "✓ armv8.mk 设备定义验证通过"
    fi

    # 验证U-Boot配置
    info "===== 验证U-Boot编译配置 ====="
    if ! grep -q "$uboot_def" "$uboot_makefile"; then
        warn "uboot Makefile 中未找到 ${uboot_def} 定义"
        error_count=$((error_count+1))
    else
        # 验证继承关系
        grep -A3 "$uboot_def" "$uboot_makefile" | grep -q "\$(U-Boot/rk3568/Default)" || {
            warn "U-Boot定义错误：${uboot_def} 未继承 U-Boot/rk3568/Default"
            error_count=$((error_count+1))
        } && info "✓ U-Boot 继承关系验证通过"

        # 验证BUILD_DEVICES语法（精准匹配Tab缩进+反斜杠）
        if grep -A5 "$uboot_def" "$uboot_makefile" | grep -q "BUILD_DEVICES := \\\\$\\n\\t\\t${DEVICE_DEF}"; then
            info "✓ U-Boot BUILD_DEVICES 语法验证通过"
        else
            warn "U-Boot BUILD_DEVICES 语法错误：需包含反斜杠+Tab缩进，且指向 ${DEVICE_DEF}"
            error_count=$((error_count+1))
        fi
        info "✓ uboot Makefile 定义验证通过"
    fi

    # 验证UBOOT_TARGETS
    if grep -q "\\b${DEVICE_NAME}-${SOC}\\b" "$uboot_makefile"; then
        info "✓ UBOOT_TARGETS 设备添加验证通过"
    else
        warn "UBOOT_TARGETS 中未找到 ${DEVICE_NAME}-${SOC}"
        error_count=$((error_count+1))
    fi

    # 验证U-Boot文件
    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    [ -f "$defconfig_dest" ] && [ -s "$defconfig_dest" ] || {
        warn "U-Boot defconfig 文件缺失/为空: $defconfig_dest"
        error_count=$((error_count+1))
    } && info "✓ U-Boot defconfig 文件验证通过"
    [ -f "$dtsi_dest" ] && [ -s "$dtsi_dest" ] || {
        warn "U-Boot dtsi 文件缺失/为空: $dtsi_dest"
        error_count=$((error_count+1))
    } && info "✓ U-Boot dtsi 文件验证通过"

    # 验证设备树（仅警告，不计数）
    if [ -f "$dts_file" ]; then
        grep -q "rk3568-xiguapi-v3-u-boot" "$dts_file" || warn "设备树文件未关联U-Boot：$dts_file 中未找到 rk3568-xiguapi-v3-u-boot 引用"
        grep -q "xiguapi-v3" "$dts_file" && info "✓ DTS文件存在且包含设备标识" || {
            warn "DTS文件存在但不包含设备标识"
            error_count=$((error_count+1))
        }
    else
        warn "DTS文件不存在: $dts_file"
        error_count=$((error_count+1))
    fi

    # 验证LED/网络/init配置
    local check_files=(
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
        "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    )
    local check_names=("LED" "网络" "初始化")
    
    for i in "${!check_files[@]}"; do
        local file="${check_files[$i]}"
        local name="${check_names[$i]}"
        
        if [ ! -f "$file" ]; then
            warn "${name}配置文件不存在: $file"
            error_count=$((error_count+1))
        elif ! grep -q "${escaped_board_name}" "$file"; then
            warn "$file 中未找到 ${BOARD_FULL_NAME} 配置"
            error_count=$((error_count+1))
        else
            info "✓ ${name}配置验证通过: $(basename "$file")"
        fi
    done

    # 检查mkimage
    command -v mkimage &>/dev/null && info "✓ U-Boot 编译工具 mkimage 已安装" || warn "U-Boot编译依赖缺失：mkimage 未安装"

    # 最终判断
    if [ $error_count -gt 0 ]; then
        error "共发现 ${error_count} 个验证错误，适配失败"
    else
        info "✓ 所有修改验证通过！U-Boot编译配置无异常"
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

main
exit 0
