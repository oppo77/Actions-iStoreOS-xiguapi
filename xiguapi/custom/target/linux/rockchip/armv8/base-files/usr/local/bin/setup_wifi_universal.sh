#!/bin/sh
# /usr/local/bin/setup_wifi_universal.sh
# 通用WiFi网卡自动识别与配置脚本
# 功能：自动识别系统中的phy无线接口，根据其能力配置双频/三频统一热点

LOG_FILE="/tmp/wifi_setup.log"
exec 1>"$LOG_FILE" 2>&1
set -x

echo "=== $(date) 开始执行通用WiFi自动配置 ==="

# ---------- 用户可修改变量 ----------
SSID="zzXGP"
ENCRYPTION="psk2"
KEY="xgpxgpxgp"
COUNTRY="CN" # 国家码，影响可用信道
# ------------------------------------

# 1. 安全地清理旧的、由脚本管理的无线设备配置
# 只删除类型为'mac80211'的radio节（现代USB/PCIe网卡），避免误删其他驱动
for radio_section in $(uci show wireless 2>/dev/null | grep -o "wireless\.radio[0-9]*" | sort -u); do
    if uci get "${radio_section}.type" 2>/dev/null | grep -q "mac80211"; then
        uci delete "$radio_section"
        echo "已删除旧配置节: $radio_section"
    fi
done
# 清理可能残留的默认接口配置
while uci delete wireless.@wifi-iface[0] 2>/dev/null; do :; done

# 2. 获取所有物理接口并遍历配置
phy_list=$(find /sys/class/ieee80211/ -name "phy*" 2>/dev/null | sort | sed 's#.*/##')
echo "系统检测到的物理接口: $phy_list"

if [ -z "$phy_list" ]; then
    echo "错误：未在 /sys/class/ieee80211/ 下找到任何无线物理接口。"
    echo "可能原因：无线驱动未加载或内核不支持。"
    exit 1
fi

radio_idx=0
for phy in $phy_list; do
    echo "--- 正在处理接口: $phy ---"
    phy_info=$(iw phy "$phy" info 2>/dev/null)
    if [ -z "$phy_info" ]; then
        echo "  警告：无法获取 $phy 的详细信息，跳过。"
        continue
    fi

    # 3. 核心：解析支持的频段 (基于标准的频率范围)
    band_2g=""; band_5g=""; band_6g=""
    if echo "$phy_info" | grep -q "24[0-9][0-9] MHz"; then
        band_2g="1"
        echo "  $phy 支持 2.4GHz 频段"
    fi
    if echo "$phy_info" | grep -q "5[0-9][0-9][0-9] MHz"; then
        band_5g="1"
        echo "  $phy 支持 5GHz 频段"
    fi
    if echo "$phy_info" | grep -q "6[0-9][0-9][0-9] MHz"; then
        band_6g="1"
        echo "  $phy 支持 6GHz 频段"
    fi

    # 确定此phy的主要频段（优先级：6G > 5G > 2G）
    band=""
    hwmode=""
    htmode=""
    if [ -n "$band_6g" ]; then
        band="6g"
        hwmode="11a"
        # 检查HE能力以设置Wi-Fi 6E/7模式
        if echo "$phy_info" | grep -qi "HE PHY Capabilities"; then
            htmode="HE80" # 可根据硬件调整为 HE160
        else
            htmode="VHT80" # 回退模式
        fi
    elif [ -n "$band_5g" ]; then
        band="5g"
        hwmode="11a"
        if echo "$phy_info" | grep -qi "HE PHY Capabilities"; then
            htmode="HE80"
        elif echo "$phy_info" | grep -qi "VHT Capabilities"; then
            htmode="VHT80"
        else
            htmode="HT20"
        fi
    elif [ -n "$band_2g" ]; then
        band="2g"
        hwmode="11g"
        if echo "$phy_info" | grep -qi "HE PHY Capabilities"; then
            htmode="HE20" # 2.4GHz的Wi-Fi 6模式
        else
            htmode="HT20"
        fi
    else
        echo "  警告：$phy 未识别到支持的频段，跳过配置。"
        continue
    fi

    # 4. 创建UCI配置
    radio_name="radio${radio_idx}"
    iface_name="default_${radio_name}"

    echo "  > 正在创建配置: UCI设备[$radio_name], 频段[$band], 模式[$htmode]"

    # 创建设备节
    uci set wireless."$radio_name"='wifi-device'
    uci set wireless."$radio_name".type='mac80211'
    uci set wireless."$radio_name".phy="$phy"
    uci set wireless."$radio_name".hwmode="$hwmode"
    uci set wireless."$radio_name".band="$band"
    uci set wireless."$radio_name".channel='auto'
    uci set wireless."$radio_name".htmode="$htmode"
    uci set wireless."$radio_name".disabled='0'
    uci set wireless."$radio_name".country="$COUNTRY"

    # 创建接入点接口节
    uci add wireless wifi-iface
    uci rename wireless.@wifi-iface[-1]="$iface_name"
    uci set wireless."$iface_name".device="$radio_name"
    uci set wireless."$iface_name".mode='ap'
    uci set wireless."$iface_name".network='lan'
    uci set wireless."$iface_name".ssid="$SSID"
    uci set wireless."$iface_name".encryption="$ENCRYPTION"
    uci set wireless."$iface_name".key="$KEY"
    uci set wireless."$iface_name".disabled='0'

    radio_idx=$((radio_idx + 1))
done

# 5. 提交配置并重启无线服务
if [ $radio_idx -eq 0 ]; then
    echo "错误：未能为任何物理接口生成有效配置。"
    exit 1
fi

echo "提交UCI配置，共配置了 $radio_idx 个无线接口。"
uci commit wireless

# 重启无线服务（采用稳健的方式）
echo "重新启动无线服务..."
wifi down 2>/dev/null
sleep 2
wifi up 2>/dev/null

# 6. 最终状态检查
echo "=== $(date) 配置执行完毕 ==="
echo "当前无线配置摘要:"
uci show wireless | grep -E "\.(phy|band|ssid|disabled)=" | sort

# 返回成功
exit 0
