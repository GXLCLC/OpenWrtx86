# ImmortalWrt X86_64 云编译

基于 [GitHub Actions](https://github.com/features/actions) 的 ImmortalWrt 云编译仓库，全自动拉取 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) **master 分支**最新源码（最新内核），仅编译 **X86_64** 架构固件，编译成功后自动发布到 GitHub Releases。

## 固件特性

- **目标平台**: X86_64（Ubuntu 22.04 运行器编译，全程自动化无交互，无 SSH 登录操作）
- **镜像格式**: squashfs combined IMG 镜像（BIOS + EFI 双引导，gzip 压缩），仅输出 IMG，不生成 VHDX/VMDK/VDI 等其他格式
- **可写空间**: rootfs 分区 3072MB，其中 rootfs_data(/overlay) 预留约 2GB，用于运行时安装软件包、存放缓存及保存配置
- **驱动支持**: 内置 USB 驱动、USB 网卡驱动，同时包含英特尔(Intel)、瑞昱(Realtek)系列有线网卡驱动
- **代理插件**: 仅集成 **OpenClash** 这一个代理类插件，不含其他任何代理类插件
- **默认设置**（由 [scripts/system-settings.sh](scripts/system-settings.sh) 统一管理）:
  - LAN IP: `192.168.1.1`
  - 后台账号: `root` / 密码: `password`（首次登录后请及时修改）
  - 主机名: `ImmortalWrt`
  - 默认主题: **Argon**（含 argon-config 主题设置界面）
  - 时区: `Asia/Shanghai`

## 内置插件清单

| 插件 | 说明 |
| :--- | :--- |
| luci-app-openclash | OpenClash 代理客户端（唯一代理类插件） |
| luci-app-smartdns + smartdns | SmartDNS 高性能 DNS 分流 |
| luci-app-adguardhome + adguardhome | AdGuardHome 全网广告过滤 |
| luci-app-ddnsto + ddnsto | DDNSTO 远程控制 |
| luci-app-oaf + appfilter + kmod-oaf | OAF 应用过滤（OpenAppFilter） |
| luci-app-turboacc | Turbo ACC 网络加速（流量分载 + BBR） |
| luci-app-mwan3 + mwan3 | Mwan3 多 WAN 负载均衡/故障切换 |
| luci-app-nlbwmon + nlbwmon | 带宽监控（按 IP 统计流量） |
| luci-app-easytier + easytier | EasyTier 去中心化内网穿透组网 |
| luci-theme-argon + luci-app-argon-config | Argon 主题（默认）及主题设置 |

## 使用方法

### 直接使用

1. 点击仓库右上角 **Fork** 将本仓库 Fork 到自己的 GitHub 账号下
2. 进入自己 Fork 的仓库 → **Actions** 页面 → 选择 **ImmortalWrt 云编译(X86_64)** 工作流 → **Run workflow** 手动触发编译
3. 等待编译完成（首次编译约 2~4 小时，后续命中缓存会明显加快）
4. 编译成功后在仓库 **Releases** 页面下载固件镜像（`*-squashfs-combined*.img.gz`），Release 说明中自动包含 LAN IP、登录账号密码、内核版本、固件版本与插件清单
5. 解压 gzip 后按需刷入:
   - `*-squashfs-combined.img.gz` — BIOS(Legacy/MBR) 引导镜像
   - `*-squashfs-combined-efi.img.gz` — EFI(GPT) 引导镜像

### 自定义固件（增减插件）

编辑仓库内的 [config/x86_64.config](config/x86_64.config):

- **增加插件**: 添加一行 `CONFIG_PACKAGE_插件名=y`
- **移除插件**: 删除对应行，或改为 `# CONFIG_PACKAGE_插件名 is not set`
- 提交修改后重新触发编译即可生效，配置经 `make defconfig` 非交互展开依赖，无需 menuconfig 操作

其他可自定义项:

| 文件/目录 | 用途 |
| :--- | :--- |
| [config/x86_64.config](config/x86_64.config) | 编译配置（插件/驱动/镜像格式/分区大小） |
| [scripts/system-settings.sh](scripts/system-settings.sh) | 系统默认设置（LAN IP/登录密码/主机名/默认主题/时区），修改此一个文件即可全处同步（固件 + Release 说明） |
| [scripts/diy-part1.sh](scripts/diy-part1.sh) | feeds 更新前的自定义修改（如软件源增删） |
| [scripts/diy-part2.sh](scripts/diy-part2.sh) | 第三方插件按需拉取配置（增删第三方插件源） |
| [.github/workflows/build-openwrt.yml](.github/workflows/build-openwrt.yml) | 编译工作流（源码仓库/分支等全局参数，每一步均有中文注释） |

## 第三方插件拉取规则

遵循 **"仅补缺"** 原则：优先使用 ImmortalWrt 源码自带软件包，仅当 ImmortalWrt 源码仓库不存在对应软件包时，才从第三方仓库通过 `git sparse-checkout` **浅克隆所需插件目录**（不完整拉取整个仓库），节省编译耗时:

| 软件包 | 第三方仓库 | 分支 | 拉取目录 |
| :--- | :--- | :--- | :--- |
| luci-app-turboacc | [coolsnowwolf/luci](https://github.com/coolsnowwolf/luci) | openwrt-25.12 | `applications/luci-app-turboacc` |
| luci-app-easytier + easytier | [EasyTier/luci-app-easytier](https://github.com/EasyTier/luci-app-easytier) | main | `luci-app-easytier` / `easytier` |
| luci-app-ddnsto | [linkease/nas-packages-luci](https://github.com/linkease/nas-packages-luci) | main | `luci/luci-app-ddnsto` |
| ddnsto（后端） | [linkease/nas-packages](https://github.com/linkease/nas-packages) | master | `network/services/ddnsto` |
| luci-app-oaf | [destan19/OpenAppFilter](https://github.com/destan19/OpenAppFilter) | master | `luci-app-oaf` |
| (备用源) smartdns / adguardhome / argon 系列等 | [kenzok8/openwrt-packages](https://github.com/kenzok8/openwrt-packages) | master | 对应同名目录 |

> 说明: DDNSTO 拉取时同时拉取 LuCI 前端（nas-packages-luci）与后端程序包（nas-packages），并非仅拉取 luci 页面目录。
> 当前 SmartDNS、AdGuardHome、OpenClash、Mwan3、带宽监控(nlbwmon)、Argon 主题及 OAF 的后端（appfilter + kmod-oaf，位于 feeds 的 `open-app-filter` 目录）均由 ImmortalWrt feeds 自带；kenzok8 仓库仅作为 ImmortalWrt 未来移除对应包时的备用源（自动按需启用，无需修改脚本）。
> 软件包存在性检测采用「目录名 + Makefile 包定义」双重匹配，可正确识别目录名与包名不一致的情况（如 `open-app-filter` 目录内的 appfilter/kmod-oaf 包），避免第三方重复拉取同名包引发 Kconfig 递归依赖与内核编译失败。

## 工作流说明

[.github/workflows/build-openwrt.yml](.github/workflows/build-openwrt.yml) 执行流程（每一步均详细中文注释）:

1. **磁盘扩容**: 清理 Runner 预装软件（Android SDK/.NET 等），释放 20GB+ 空间，规避磁盘不足导致编译失败
2. **源码缓存**: `actions/cache` 缓存 ImmortalWrt 源码(.git)与 feeds，命中后增量更新，减少重复拉取耗时
3. **dl 缓存**: 缓存源码包下载目录（dl），跳过大部分软件包下载
4. **feeds 依赖处理**: 编译前执行 `feeds update -a && feeds install -a`
5. **按需拉取第三方插件**（见上文拉取规则）
6. **注入系统默认配置**: 执行独立脚本 `scripts/system-settings.sh`，将 LAN IP/登录密码/主机名/默认主题注入固件（首次开机自动生效）
7. **配置展开**: 载入 `config/x86_64.config` 后 `make defconfig` 非交互展开依赖，并校验关键插件全部启用（防配置被静默丢弃）
8. **自动编译**: 下载校验 → 多线程编译，**任一步骤出错立即终止工作流**
9. **自动发布**: 生成含 LAN IP、账号密码、内核版本、固件版本、插件清单（每行一个插件名称，不含 kmod 等驱动依赖）的发布说明，自动创建 GitHub Releases 并上传 IMG 镜像

## 感谢

- [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) — ImmortalWrt 源码
- [coolsnowwolf/luci](https://github.com/coolsnowwolf/luci) — Turbo ACC 网络加速
- [EasyTier/luci-app-easytier](https://github.com/EasyTier/luci-app-easytier) — EasyTier 内网穿透
- [linkease/nas-packages-luci](https://github.com/linkease/nas-packages-luci) / [linkease/nas-packages](https://github.com/linkease/nas-packages) — DDNSTO 相关插件
- [destan19/OpenAppFilter](https://github.com/destan19/OpenAppFilter) — OAF 应用过滤
- [kenzok8/openwrt-packages](https://github.com/kenzok8/openwrt-packages) — 第三方插件仓库（备用源）
- [softprops/action-gh-release](https://github.com/softprops/action-gh-release) — Release 发布动作
- [GitHub Actions](https://github.com/features/actions) — 云编译平台

## 许可

[MIT](LICENSE)
