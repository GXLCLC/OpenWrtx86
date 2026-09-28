#!/bin/bash
# ============================================================================
# gen-release-info.sh —— 收集固件信息, 生成 GitHub Release 发布说明
#
# 执行时机: 固件编译并整理完成后(工作流步骤15)
# 输出文件: release-info.md(供 Release 发布步骤作为 body 自动填充)
# 内容包含: LAN IP、后台登录账号密码、内核版本、固件版本、
#           已安装插件清单(每行一个插件, 方便使用者快速查阅)
# 默认工作目录: 仓库根目录(LEDE 源码位于其下的 openwrt/ 目录)
# ============================================================================

# 任何命令出错立即终止脚本(与工作流"错误即终止"策略一致)
set -e

OPENWRT_DIR="${OPENWRT_DIR:-openwrt}"
OUT_FILE="release-info.md"

# ----------------------------------------------------------------------------
# 固件默认设置信息
# 注意: 以下 LAN IP 与登录账号密码必须与
#       files/etc/uci-defaults/99-custom-settings 中设置的值保持一致,
#       修改任意一处时请同步修改另一处
# ----------------------------------------------------------------------------
LAN_IP="192.168.1.1"        # 默认 LAN IP 地址
LOGIN_USER="root"           # 后台登录账号
LOGIN_PASS="password"       # 后台登录密码
DEFAULT_THEME="Argon"       # 系统默认主题

# ----------------------------------------------------------------------------
# 提取内核版本
# 说明: 从编译目录中的 linux-x.x.x 目录名提取(例: linux-6.12.30)
# ----------------------------------------------------------------------------
KERNEL_VER="$(ls -d "$OPENWRT_DIR/build_dir/target-"*/linux-x86_64/linux-* 2>/dev/null | head -n1 | sed 's|.*/linux-||')"
[ -n "$KERNEL_VER" ] || KERNEL_VER="unknown"

# ----------------------------------------------------------------------------
# 提取固件版本信息
# 说明: LEDE 为滚动更新分支(无固定版本号), 固件版本以
#       "编译日期 + LEDE 源码提交号" 唯一标识, 确保可追溯
# ----------------------------------------------------------------------------
BUILD_DATE="$(date '+%Y-%m-%d %H:%M')"
LEDE_COMMIT="$(git -C "$OPENWRT_DIR" log -1 --format='%h')"

# ----------------------------------------------------------------------------
# 提取已安装插件清单
# 说明: 从 make defconfig 展开后的 .config 中提取全部已启用的
#       LuCI 应用(luci-app-*)、LuCI 主题(luci-theme-*)及核心功能包,
#       按名称排序, 每行一个插件
# ----------------------------------------------------------------------------
PLUGIN_LIST="$(grep -oE \
    '^CONFIG_PACKAGE_(luci-app-[a-z0-9-]+|luci-theme-[a-z0-9-]+|smartdns|adguardhome|ddnsto|easytier|mwan3|nlbwmon|appfilter|oaf)=y' \
    "$OPENWRT_DIR/.config" | sed 's/^CONFIG_PACKAGE_//; s/=y$//' | sort -u)"
# 转换为 Markdown 列表(每行一个插件)
PLUGIN_MD_LIST="$(echo "$PLUGIN_LIST" | sed 's/^/- /')"

# ----------------------------------------------------------------------------
# 生成镜像文件清单(文件名 + 体积 + SHA256 校验值)
# ----------------------------------------------------------------------------
IMG_MD_LIST=""
for f in firmware/*squashfs-combined*.img.gz; do
    [ -f "$f" ] || continue
    f_size="$(du -h "$f" | awk '{print $1}')"
    f_sha256="$(sha256sum "$f" | awk '{print $1}')"
    f_name="$(basename "$f")"
    IMG_MD_LIST="${IMG_MD_LIST}- \`${f_name}\` (体积: ${f_size})
  - SHA256: \`${f_sha256}\`
"
done

# ----------------------------------------------------------------------------
# 生成 Release 发布说明文档
# ----------------------------------------------------------------------------
cat > "$OUT_FILE" <<EOF
## 固件信息

| 项目 | 内容 |
| :--- | :--- |
| 固件版本 | LEDE 滚动版本 (编译于 ${BUILD_DATE}) |
| 源码版本 | coolsnowwolf/lede @ \`${LEDE_COMMIT}\` |
| 内核版本 | Linux \`${KERNEL_VER}\` |
| 目标平台 | X86_64 (squashfs combined 镜像, BIOS + EFI 双引导) |
| 可写空间 | rootfs 分区 3072MB, 其中 rootfs_data(/overlay) 预留约 2GB, 用于运行时安装软件包、存放缓存及保存配置 |
| 镜像格式 | 仅 IMG 镜像(gzip 压缩), 不含 VHDX/VMDK/VDI 等其他格式 |

## 默认设置

- **LAN IP**: \`${LAN_IP}\`
- **后台登录账号**: \`${LOGIN_USER}\`
- **后台登录密码**: \`${LOGIN_PASS}\`
- **默认主题**: ${DEFAULT_THEME}
- 提示: 首次登录 LuCI 后台后, 请及时修改默认密码

## 已安装插件清单

${PLUGIN_MD_LIST}

## 镜像文件

${IMG_MD_LIST}
> 镜像说明: \`*-squashfs-combined.img.gz\` 为 BIOS(Legacy/MBR) 引导镜像; \`*-squashfs-combined-efi.img.gz\` 为 EFI(GPT) 引导镜像。请根据设备的引导方式选择刷入, 写入前请先解压 gzip。
EOF

echo "[release-info] 已生成发布说明 $OUT_FILE:"
echo "----------------------------------------"
cat "$OUT_FILE"
echo "----------------------------------------"
