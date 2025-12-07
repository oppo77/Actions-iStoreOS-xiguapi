# iStore OS 固件 | xiguapi-v3

[![iStore 使用文档](https://img.shields.io/badge/使用文档-iStore%20OS-brightgreen?style=flat-square)](https://doc.linkease.com/zh/guide/istoreos)
[![最新固件下载](https://img.shields.io/github/v/release/xiaomeng9597/Actions-iStoreOS-RK35XX?style=flat-square&label=最新固件下载)](../../releases/latest)

适用于 **nlnet_xiguapi-v3** 设备的定制 iStore OS 固件。

---

## 🖥️ 设备配置

| 项目 | 规格 |
|------|------|
| **厂商** | nlnet |
| **型号** | xiguapi-v3（新版本） |
| **CPU** | 瑞芯微 RK3568 四核64位Cortex-A55 Mail-G52 |
| **电源** | RK817-5（兼容rk808h）DC 12V 1.5A |
| **ROM** | 32GB eMMC（闪迪 SanDisk SDINBDA4-32G） |
| **RAM** | 4GB LPDDR4X（长鑫 CXMT CXDB5CCBM-MK-A） |
| **网络接口** | 2个 RTL8211F 千兆网口 |
| **扩展接口** | 2个 MINIPCIE 接口（带5V电源PA供电）<br>1个 M.2 B Key接口（5G模块）<br>1个 M.2 E Key接口（WiFi网卡）<br>1个 USB3.0 A口（OTG接口）<br>1个 TF卡槽<br>1个 SIM卡槽 |
| **视频输出** | 1个 HDMI2.0 接口 |
| **其他接口** | 1个 FPC SPI/I2C 显示屏接口<br>1个 5V风扇接口（MX1.25 4pin PWM调速）<br>1个 DC 5521电源插头（5V-18V 1-3A） |
| **指示灯** | 3个 LED指示灯（状态、网络、电源） |
| **按钮** | 刷机键、重启键、恢复键 |

---


### ⚙️ 固件配置

|  **编译周期**  | `北京时间每日 `0:00` 自动编译` |
|------|------|
| **版本** | `istoreos24.10.2` |
| **管理地址** | `http://192.168.100.1` 或 `http://iStoreOS.lan/` |
| **账户** | `root` |
| **密码** | `password` |



### 🌐 网络接口说明

- 一个网口默认作为 **WAN** 口，其余均为 **LAN** 口
- 如需修改 LAN 口 IP：
  - Web 首页 → "内网设置"
  - 或使用 `quickstart` 命令

---

## 📊 适配状态

### ✅ 已完成
- 制作设备树
- 制作uboot设备树
- 制作uboot补丁
- 制作defconfig
- 基础适配

### 🚀 计划中
- 修改 01_leds 脚本
- 修改 02_network
- 修改 init.sh
- 小屏幕适配

---

### ⚠️ 添加自定义插件（重要）

将自定义插件配置项添加到 **`configfiles/config_data.txt`** 文件中。

> **说明**："Sync Files" 工作流会自动获取官方t68m的config，然后将 `configfiles/config_data.txt` 与 `config` 相结合，在 armv8/ 路径生成 `.config`。


---

## 支持一杯☕️



## 🙏 鸣谢

本项目的实现离不开以下优秀项目与服务的支持：

- [iStoreOS](https://github.com/istoreos/istoreos) - 固件基础
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) - 自动化编译框架
- [OpenWrt](https://github.com/openwrt/openwrt) / [Lean's OpenWrt](https://github.com/coolsnowwolf/lede) - 开源系统
- [GitHub Actions](https://github.com/features/actions) - 自动化平台
- [Microsoft Azure](https://azure.microsoft.com) - 提供云资源
- [draco-china/istoreos-actions](https://github.com/draco-china/istoreos-actions) - 项目参考
- [xiaomeng9597/Actions-iStoreOS-RK35XX-24.10/](https://github.com/xiaomeng9597) 
- 以及所有相关工具与服务的开发者们


