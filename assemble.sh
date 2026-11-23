#!/bin/bash
# 在 GitHub Actions runner 上执行：
# 1. 下载官方 trixie-zh 容器，抽取 /opt/tiny 辅助文件、伪造 /proc 文件、pipewire 配置
# 2. 生成 Kubuntu 版 .tiny.yaml
# 3. 按 Tiny Container 要求打包为 .tar.zst（.tiny.yaml 必须是归档第一个成员）
set -euxo pipefail

ROOTFS=rootfs
mkdir -p official_dl official_rootfs

# ---- 1. 下载官方容器并抽取需要的部分 ----
# 注意：trixie-zh 是纯命令行版；桌面版的辅助文件要从 xfce-zh 抽取
gh release download --repo tiny-computer/images --pattern 'xfce-zh-*.tar.zst' --dir official_dl --clobber
ASSET=$(ls official_dl/*.tar.zst | head -n1)
# 注意：官方归档的成员名不带 ./ 前缀；某些路径（如 etc/wireplumber）可能不存在，
# tar 遇到未匹配的 --wildcards 模式会以退出码 2 结束，这里显式容忍，靠后续 test 校验必需文件。
set +e
zstd -dc --long=31 --memory=2048MB "$ASSET" | tar -C official_rootfs -x --wildcards \
  '.tiny.yaml' \
  'opt/tiny/*' \
  'proc/.*' \
  'sys/.*' \
  'etc/pipewire/*' 'etc/pipewire-pulse/*' 'etc/wireplumber/*' \
  'home/tiny/.config/pipewire/*' 'home/tiny/.config/wireplumber/*'
set -e
rm -f "$ASSET"

echo "=== extracted tree ==="
ls -la official_rootfs || true
ls -la official_rootfs/opt 2>/dev/null || true
ls -la official_rootfs/opt/tiny 2>/dev/null || true
ls -la official_rootfs/proc 2>/dev/null || true

# 校验必需文件
test -f official_rootfs/.tiny.yaml
test -d official_rootfs/opt/tiny
test -f official_rootfs/proc/.loadavg

# ---- 2. 覆盖到 Kubuntu rootfs ----
sudo cp -a official_rootfs/opt "$ROOTFS"/
sudo cp -a official_rootfs/proc/. "$ROOTFS"/proc/
sudo cp -a official_rootfs/sys/. "$ROOTFS"/sys/

for d in pipewire pipewire-pulse wireplumber; do
  if [ -d "official_rootfs/etc/$d" ]; then
    sudo rm -rf "$ROOTFS/etc/$d"
    sudo cp -a "official_rootfs/etc/$d" "$ROOTFS/etc/$d"
  fi
done

if [ -d official_rootfs/home/tiny/.config ]; then
  sudo mkdir -p "$ROOTFS/home/tiny/.config"
  sudo cp -a official_rootfs/home/tiny/.config/. "$ROOTFS/home/tiny/.config/"
  sudo chown -R 1000:1000 "$ROOTFS/home/tiny/.config" || true
fi

# ---- 3. 生成 Kubuntu 版 .tiny.yaml ----
python3 - <<'PY'
import yaml

src = 'official_rootfs/.tiny.yaml'
text = open(src, encoding='utf-8').read()
# Xfce 会话替换为 Plasma X11 会话
text = text.replace('startxfce4', 'startplasma-x11')
d = yaml.safe_load(text)

d['code'] = 'kubuntu2404'
d['name'] = 'Kubuntu 24.04'
d['description'] = (
    'Kubuntu 24.04 LTS（KDE Plasma，arm64）容器，适配小小容器（Tiny Container）。\n'
    '图形会话为 KDE Plasma X11（startplasma-x11），在“功能”页启用 X11 或 AVNC 前端后重启容器即可进入桌面。\n'
    '登录用户 tiny（密码 tiny），root 密码 tiny，tiny 免密 sudo。\n'
    '构建脚本见仓库 build.sh / assemble.sh / .github/workflows/build.yml。'
)

with open(src, 'w', encoding='utf-8') as f:
    yaml.dump(d, f, allow_unicode=True, sort_keys=False, width=100000)
print('.tiny.yaml rewritten for Kubuntu')
PY

sudo cp official_rootfs/.tiny.yaml "$ROOTFS/.tiny.yaml"

# ---- 4. 打包：.tiny.yaml 必须是归档第一个成员 ----
STAMP=$(date +%Y%m%d-%H%M%S)
BASE="kubuntu-zh-${STAMP}"

sudo tar -C "$ROOTFS" --numeric-owner -cf /tmp/out.tar .tiny.yaml
sudo tar -C "$ROOTFS" --numeric-owner --exclude='./.tiny.yaml' --exclude='./dev/*' -rf /tmp/out.tar .
zstd -10 -T0 /tmp/out.tar -o "${BASE}.tar.zst"
rm -f /tmp/out.tar

# GitHub Release 单文件上限 2GB，超限自动分卷
SIZE=$(stat -c%s "${BASE}.tar.zst")
if [ "$SIZE" -gt 1990000000 ]; then
  split -b 1900M -d "${BASE}.tar.zst" "${BASE}.tar.zst.part-"
  rm -f "${BASE}.tar.zst"
fi

ls -lh ${BASE}*
df -h /
echo "BASE=${BASE}" >> "$GITHUB_ENV"
