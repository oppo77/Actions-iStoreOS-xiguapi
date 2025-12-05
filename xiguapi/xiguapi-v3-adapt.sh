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
UBOOT_CONFIG="rk3568-xiguapi-v3"  # 仅用于DTS命名，U-Boot定义中不再使用
# 统一board名称（匹配OpenWRT标准格式：厂商,设备名）
BOARD_FULL_NAME="nlnet,${DEVICE_NAME}"
# 网卡驱动可配置变量（按你的要求保留，未修改）
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
    # 调试：输出关键文件内容帮助定位问题
    if [ -f "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds" ]; then
        echo -e "\033[31m[DEBUG] 01_leds 文件内容片段：\033[0m"
        grep -A10 -B2 "${BOARD_FULL_NAME//,/\\,}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds" || true
    fi
    exit 1;
}

ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir" || error "创建目录失败: $dir"
        info "创建目录: $dir"
    fi
}

# 简化：移除备份逻辑，仅保留文件复制
copy_file() {
    local src="$1"
    local dest="$2"
    ensure_dir "$(dirname "$dest")"
    
    if [ ! -f "$src" ]; then
        error "源文件不存在: $src"
    fi
    
    # 直接覆盖（新环境无需备份）
    cp -f "$src" "$dest" || error "复制文件失败: $src -> $dest"
    info "复制文件: $src -> $dest"
}

# ===================== 核心操作函数 =====================
init_check() {
    info "===== 1. 初始化检查 ====="
    info "脚本目录: ${SCRIPT_DIR}"
    info "源码根目录: ${SOURCE_ROOT_DIR}"

    # 检查关键设备文件
    local required_files=(
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig"
        "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi"
    )
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "必需设备文件缺失: $file"
        fi
    done
    info "所有必需设备文件验证通过"

    # 新增：检查U-Boot核心依赖（rk3568 Default定义是否存在）
    local uboot_default_def="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    if ! grep -q "define U-Boot/rk3568/Default" "$uboot_default_def"; then
        error "U-Boot核心依赖缺失：未找到 U-Boot/rk3568/Default 定义，请检查uboot-rockchip包是否完整"
    fi
    info "U-Boot rk3568 Default 依赖验证通过"

    # 切换工作目录到源码根目录
    cd "${SOURCE_ROOT_DIR}" || error "无法进入源码根目录: ${SOURCE_ROOT_DIR}"
    info "当前工作目录: $(pwd)"

    # 脚本执行权限检查
    if [ ! -x "${BASH_SOURCE[0]}" ]; then
        warn "脚本无执行权限，自动添加..."
        chmod +x "${BASH_SOURCE[0]}" || error "添加执行权限失败"
    fi
}

copy_device_files() {
    info "===== 2. 复制设备文件 ====="
    
    # 补全所有目标路径为绝对路径
    local dts_dest="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/rk3568-xiguapi-v3.dts"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3.dts" "$dts_dest"

    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3_defconfig" "$defconfig_dest"

    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    copy_file "${DEVICE_FILES_DIR}/rk3568-xiguapi-v3-u-boot.dtsi" "$dtsi_dest"

    # 验证U-Boot文件复制完整性
    info "===== 验证U-Boot文件复制结果 ====="
    local uboot_copy_files=(
        "$defconfig_dest"
        "$dtsi_dest"
    )
    for file in "${uboot_copy_files[@]}"; do
        if [ ! -f "$file" ]; then
            error "U-Boot文件复制失败：$file 不存在"
        elif [ ! -s "$file" ]; then
            error "U-Boot文件复制异常：$file 为空文件"
        else
            info "✓ U-Boot文件验证通过: $file"
        fi
    done

    # 【移除】自动添加U-Boot dtsi引用的逻辑，保留设备树未关联的警告
}

modify_armv8_mk() {
    info "===== 3. 修改armv8.mk ====="
    local armv8_mk="${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"
    local armv8_dir=$(dirname "$armv8_mk")

    # 确保目录存在
    ensure_dir "$armv8_dir"

    # 避免重复添加
    if grep -q "define Device/${DEVICE_DEF}" "$armv8_mk"; then
        warn "${DEVICE_DEF} 已存在于 armv8.mk，跳过追加"
        return
    fi

    # 添加设备定义
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

    # 添加U-Boot定义（官方格式：设备名-soc）
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"
    if ! grep -q "$uboot_def" "$uboot_makefile"; then
        # 修复：BUILD_DEVICES 正确格式（反斜杠+换行+Tab缩进）
        cat >> "$uboot_makefile" << EOF

# Added for Xiguapi V3 (rk3568)
define ${uboot_def}
  \$(U-Boot/rk3568/Default)  # 继承RK3568默认依赖/ATF/TPL配置
  NAME:=Xiguapi V3
  BUILD_DEVICES := \\
	${DEVICE_DEF}            # 对应armv8.mk中的DEVICE_DEF
endef
EOF
        info "已添加 ${uboot_def} 定义（继承RK3568默认配置）"
    else
        warn "${uboot_def} 已存在，跳过"
    fi

    # 修复：UBOOT_TARGETS 添加逻辑（兼容行首空格，精准匹配）
    local target_device="${DEVICE_NAME}-${SOC}"
    if ! grep -q "\\b${target_device}\\b" "$uboot_makefile"; then
        # 匹配任意行首空格的UBOOT_TARGETS行，追加设备名
        sed -i "/^[[:space:]]*UBOOT_TARGETS[[:space:]]*:=/ s/\$/ ${target_device}/" "$uboot_makefile"
        info "已添加 ${target_device} 到 UBOOT_TARGETS"
    else
        warn "${target_device} 已在UBOOT_TARGETS中，跳过"
    fi
}

modify_device_configs() {
    info "===== 5. 修改设备配置文件 ====="
    
    # 修复01_leds配置
    local leds_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/01_leds"
    
    # 检查文件是否存在
    if [ ! -f "$leds_file" ]; then
        error "LED配置文件不存在: $leds_file。请确保OpenWRT源码完整"
    fi

    # 检查是否已存在
    if grep -q "${BOARD_FULL_NAME//,/\\,}" "$leds_file"; then
        warn "${DEVICE_NAME} LED配置已存在，跳过"
    else
        # 在esac行前插入（简单可靠的方法）
        local leds_config="${BOARD_FULL_NAME})
	ucidef_set_led_default \"power\" \"POWER\" \"blue:power\" \"1\"
	ucidef_set_led_netdev \"status\" \"STATUS\" \"blue:status\" \"eth0\"
	ucidef_set_led_netdev \"network\" \"NETWORK\" \"blue:network\" \"eth1\"
	;;"
        
        # 使用临时文件确保插入正确
        local tmp_file=$(mktemp)
        awk -v config="$leds_config" '
            /^esac$/ {
                print config
            }
            { print }
        ' "$leds_file" > "$tmp_file" && mv "$tmp_file" "$leds_file"
        
        info "已添加 ${DEVICE_NAME} LED配置"
    fi

    # 修改02_network配置
    local network_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/etc/board.d/02_network"
    
    # 检查文件是否存在
    if [ ! -f "$network_file" ]; then
        error "网络配置文件不存在: $network_file。请确保OpenWRT源码完整"
    fi

    # 检查是否已存在
    if grep -q "${BOARD_FULL_NAME//,/\\,}" "$network_file"; then
        warn "${DEVICE_NAME} 网络配置已存在，跳过"
    else
        # 接口配置 - 在rockchip_setup_interfaces函数的默认case前插入
        local network_iface_config="${BOARD_FULL_NAME})
	ucidef_set_interfaces_lan_wan \"eth0\" \"eth1\"
	;;"
        
        local tmp_file=$(mktemp)
        awk -v config="$network_iface_config" '
            /rockchip_setup_interfaces\(\)/,/^\s*\*\)/ {
                if (/^\s*\*\)/) {
                    print config
                }
            }
            { print }
        ' "$network_file" > "$tmp_file" && mv "$tmp_file" "$network_file"
        
        # MAC地址配置 - 在rockchip_setup_macs函数的默认case前插入
        local network_mac_config="${BOARD_FULL_NAME})
	wan_mac=\$(generate_mac_from_boot_mmc)
	lan_mac=\$(macaddr_add \"\$wan_mac\" 1)
	;;"
        
        local tmp_file2=$(mktemp)
        awk -v config="$network_mac_config" '
            /rockchip_setup_macs\(\)/,/^\s*\*\)/ {
                if (/^\s*\*\)/) {
                    print config
                }
            }
            { print }
        ' "$network_file" > "$tmp_file2" && mv "$tmp_file2" "$network_file"
        
        info "已添加 ${DEVICE_NAME} 网络配置"
    fi

    # 修改init.sh配置
    local init_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/armv8/base-files/lib/board/init.sh"
    
    # 检查文件是否存在
    if [ ! -f "$init_file" ]; then
        error "初始化配置文件不存在: $init_file。请确保OpenWRT源码完整"
    fi

    # 检查是否已存在
    if grep -q "${BOARD_FULL_NAME//,/\\,}" "$init_file"; then
        warn "${DEVICE_NAME} 初始化配置已存在，跳过"
    else
        # 接口修复 - 在board_fixup_iface_name函数的默认case前插入
        local init_iface_config="${BOARD_FULL_NAME})
	# No interface renaming needed
	;;"
        
        local tmp_file=$(mktemp)
        awk -v config="$init_iface_config" '
            /board_fixup_iface_name\(\)/,/^\s*\*\)/ {
                if (/^\s*\*\)/) {
                    print config
                }
            }
            { print }
        ' "$init_file" > "$tmp_file" && mv "$tmp_file" "$init_file"
        
        # SMP亲和性 - 在board_set_iface_smp_affinity函数的默认case前插入
        local init_smp_config="${BOARD_FULL_NAME})
	set_iface_cpumask 2 eth0
	set_iface_cpumask 4 eth1
	;;"
        
        local tmp_file2=$(mktemp)
        awk -v config="$init_smp_config" '
            /board_set_iface_smp_affinity\(\)/,/^\s*\*\)/ {
                if (/^\s*\*\)/) {
                    print config
                }
            }
            { print }
        ' "$init_file" > "$tmp_file2" && mv "$tmp_file2" "$init_file"
        
        info "已添加 ${DEVICE_NAME} 初始化配置"
    fi
}

verify_changes() {
    info "===== 6. 验证修改结果 ====="
    local error_count=0
    local dts_file="${SOURCE_ROOT_DIR}/target/linux/rockchip/dts/rk3568/${UBOOT_CONFIG}.dts"
    local uboot_makefile="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/Makefile"
    local uboot_def="U-Boot/${DEVICE_NAME}-${SOC}"
    local escaped_board_name="${BOARD_FULL_NAME//,/\\,}"

    # 验证设备定义
    if ! grep -q "define Device/${DEVICE_DEF}" "${SOURCE_ROOT_DIR}/target/linux/rockchip/image/armv8.mk"; then
        warn "armv8.mk 中未找到 ${DEVICE_DEF} 设备定义"
        error_count=$((error_count+1))
    else
        info "✓ armv8.mk 设备定义验证通过"
    fi

    # U-Boot 深度编译验证
    info "===== 验证U-Boot编译配置 ====="
    # 1. 验证U-Boot定义是否存在且语法正确
    if ! grep -q "$uboot_def" "$uboot_makefile"; then
        warn "uboot Makefile 中未找到 ${uboot_def} 定义"
        error_count=$((error_count+1))
    else
        # 验证继承关系
        if ! grep -A3 "$uboot_def" "$uboot_makefile" | grep -q "\$(U-Boot/rk3568/Default)"; then
            warn "U-Boot定义错误：${uboot_def} 未继承 U-Boot/rk3568/Default"
            error_count=$((error_count+1))
        else
            info "✓ U-Boot 继承关系验证通过"
        fi

        # 验证BUILD_DEVICES语法
        if ! grep -A5 "$uboot_def" "$uboot_makefile" | grep -q "BUILD_DEVICES.*\\\\[[:space:]]*${DEVICE_DEF}"; then
            warn "U-Boot BUILD_DEVICES 语法错误：需包含反斜杠+缩进，且指向 ${DEVICE_DEF}"
            error_count=$((error_count+1))
        else
            info "✓ U-Boot BUILD_DEVICES 语法验证通过"
        fi
        info "✓ uboot Makefile 定义验证通过"
    fi

    # 2. 验证UBOOT_TARGETS添加
    if ! grep -q "UBOOT_TARGETS.*${DEVICE_NAME}-${SOC}" "$uboot_makefile"; then
        warn "UBOOT_TARGETS 中未找到 ${DEVICE_NAME}-${SOC}"
        error_count=$((error_count+1))
    else
        info "✓ UBOOT_TARGETS 设备添加验证通过"
    fi

    # 3. 验证U-Boot编译文件完整性
    local defconfig_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/configs/${UBOOT_CONFIG}_defconfig"
    local dtsi_dest="${SOURCE_ROOT_DIR}/package/boot/uboot-rockchip/src/arch/arm/dts/rk3568-xiguapi-v3-u-boot.dtsi"
    if [ ! -f "$defconfig_dest" ] || [ ! -s "$defconfig_dest" ]; then
        warn "U-Boot defconfig 文件缺失/为空: $defconfig_dest"
        error_count=$((error_count+1))
    else
        info "✓ U-Boot defconfig 文件验证通过"
    fi
    if [ ! -f "$dtsi_dest" ] || [ ! -s "$dtsi_dest" ]; then
        warn "U-Boot dtsi 文件缺失/为空: $dtsi_dest"
        error_count=$((error_count+1))
    else
        info "✓ U-Boot dtsi 文件验证通过"
    fi

    # 4. 验证U-Boot与设备树关联（仅保留警告，不做修复）
    if [ -f "$dts_file" ]; then
        if grep -q "rk3568-xiguapi-v3-u-boot" "$dts_file"; then
            info "✓ 设备树文件正确引用了U-Boot dtsi"
        else
            warn "设备树文件未关联U-Boot：$dts_file 中未找到 rk3568-xiguapi-v3-u-boot 引用"
            # 保留警告，不修改error_count
        fi
    fi

    # 验证DTS文件
    if [ ! -f "$dts_file" ]; then
        warn "DTS文件不存在: $dts_file"
        error_count=$((error_count+1))
    else
        if grep -q "xiguapi-v3" "$dts_file"; then
            info "✓ DTS文件存在且包含设备标识"
        else
            warn "DTS文件存在但不包含设备标识"
            error_count=$((error_count+1))
        fi
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

    # 检查U-Boot编译依赖工具
    if ! command -v mkimage &>/dev/null; then
        warn "U-Boot编译依赖缺失：mkimage 未安装（编译时可能失败）"
    else
        info "✓ U-Boot 编译工具 mkimage 已安装"
    fi

    # 最后统一判断是否退出
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
