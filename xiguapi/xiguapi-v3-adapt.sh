modify_armv8_mk() {
    info "===== 3. 修改armv8.mk（插入到include legacy.mk之前） ====="
    local armv8_mk="target/linux/rockchip/image/armv8.mk"
    local device_tag="nlnet_xiguapi-v3"
    local device_comment="# Added for Xiguapi V3 (rk3568)"
    
    # 前置检查
    if [ ! -f "$armv8_mk" ]; then
        error "错误：${armv8_mk} 文件不存在！"
        return 1
    fi
    if [ ! -w "$armv8_mk" ]; then
        error "错误：${armv8_mk} 无写入权限！"
        return 1
    fi

    # 关键：精准找到include legacy.mk的行号（排除注释行）
    # Linux/macOS兼容的行号查找
    local legacy_line
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS sed/awk
        legacy_line=$(awk '/^include legacy\.mk$/ {print NR}' "$armv8_mk")
    else
        # Linux grep
        legacy_line=$(grep -n "^include legacy\.mk$" "$armv8_mk" | cut -d: -f1)
    fi

    if [ -z "$legacy_line" ] || [ "$legacy_line" -lt 1 ]; then
        error "错误：${armv8_mk} 中未找到有效行的 'include legacy.mk'！"
        return 1
    fi
    info "找到include legacy.mk在第 ${legacy_line} 行，将插入到该行之前"

    # 第一步：删除原有重复配置（避免多次运行重复）
    sed -i.bak "/^[[:space:]]*${device_comment}/,/^TARGET_DEVICES += ${device_tag}/d" "$armv8_mk"
    rm -f "${armv8_mk}.bak"

    # 第二步：生成临时配置文件（无转义，纯文本）
    local tmp_config=$(mktemp)
    cat > "$tmp_config" << EOF
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
TARGET_DEVICES += ${device_tag}

EOF

    # 第三步：按行号插入（核心：用行号规避字符转义）
    if [[ "$(uname -s)" == "Darwin" ]]; then
        # macOS sed 按行号插入（-i '' 是macOS要求）
        sed -i '' "${legacy_line}i\\
$(cat "$tmp_config")" "$armv8_mk"
    else
        # Linux sed 按行号插入（r命令读取临时文件到指定行前）
        sed -i "${legacy_line}r $tmp_config" "$armv8_mk"
    fi

    # 删除临时文件
    rm -f "$tmp_config"

    # 验证插入结果（必须在include legacy.mk之前）
    local insert_check=$(grep -B100 "^include legacy\.mk$" "$armv8_mk" | grep -c "define Device/${device_tag}")
    if [ "$insert_check" -gt 0 ]; then
        info "✓ ${device_tag} 已精准插入到include legacy.mk第 ${legacy_line} 行之前"
    else
        error "armv8.mk配置插入失败！请检查：
1. include legacy.mk行号是否正确：${legacy_line}
2. 临时文件是否生成正常
3. 目标文件是否有写入权限"
        return 1
    fi

    return 0
}
