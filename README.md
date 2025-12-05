# iStore OS 固件 | xiguapi-v3

[![iStore 使用文档](https://img.shields.io/badge/使用文档-iStore%20OS-brightgreen?style=flat-square)](https://doc.linkease.com/zh/guide/istoreos)
[![最新固件下载](https://img.shields.io/github/v/release/xiaomeng9597/Actions-iStoreOS-RK35XX?style=flat-square&label=最新固件下载)](../../releases/latest)

适用于 **nlnet_xiguapi-v3** 设备的定制 iStore OS 固件。

---

## 📦 默认配置

| 项目 | 值 |
| :--- | :--- |
| **管理地址** | `http://192.168.100.1` 或 `http://iStoreOS.lan/` |
| **用户名** | `root` |
| **密码** | `password` |

### 🌐 网络接口说明
- 若设备仅有一个网口，则该网口为 **LAN** 口。
- 若设备有多个网口，则第一个网口默认作为 **WAN** 口，其余均为 **LAN** 口。
- 如需修改 LAN 口 IP，可在 Web 首页的“内网设置”中操作，或使用 `quickstart` 命令。

---

目前情况与未来计划



## 🛠️ 固件与定制说明

### 发布与更新
- **编译周期**：北京时间每日 `0:00` 自动编译。
- **版本策略**：`Release` 中仅保留各架构的最新版本。
- **历史版本**：在 `Actions` 中选择已成功完成的 `workflow`，于页面底部登录 GitHub 后下载 `Artifacts`。

### ⚠️ 重要：添加自定义插件
**请务必遵守以下规则，否则自定义配置可能丢失：**

- **标准流程（推荐）**：将插件配置项添加到仓库的 **`configfiles/config_data.txt`** 文件中。
    > **原因**：每日定时执行的 “Sync Files” 工作流会自动将 `.config` 文件更新为 iStoreOS 官方最新版本，直接修改 `.config` 文件会导致添加的配置被覆盖。

- **高级定制**：如果**禁用了** “Sync Files” 工作流，则需直接将插件配置项添加到 **`rk35xx/.config`** 文件中。
- **说明**：“Sync Files” 工作流会自动获取官方t68m的config，然后把`configfiles/config_data.txt`和`config`相结合在armv8/路径生成.config。

---

## 📁 设备与固件对应表

### RK35xx 架构

| 设备 | 固件文件 |
| :--- | :--- |
| **nlnet_xiguapi-v3** | `istoreos-rockchip-rk35xx-nlnet_xiguapi-v3-squashfs-combined.img.gz` |

---

## 🙏 鸣谢

本项目的实现离不开以下优秀项目与服务的支持：

- [iStoreOS](https://github.com/istoreos/istoreos) - 固件基础
- [P3TERX/Actions-OpenWrt](https://github.com/P3TERX/Actions-OpenWrt) - 自动化编译框架
- [OpenWrt](https://github.com/openwrt/openwrt) / [Lean‘s OpenWrt](https://github.com/coolsnowwolf/lede) - 开源系统
- [GitHub Actions](https://github.com/features/actions) - 自动化平台
- [Microsoft Azure](https://azure.microsoft.com) - 提供云资源
- [draco-china/istoreos-actions](https://github.com/draco-china/istoreos-actions) - 项目参考
- [xiaomeng9597/Actions-iStoreOS-RK35XX-24.10/](https://github.com/xiaomeng9597) 
- 以及所有列在原始文件中的工具与服务的开发者们。
