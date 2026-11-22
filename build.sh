#!/bin/bash
# 在 qemu-aarch64 chroot 内以 root 执行（Ubuntu 24.04 arm64 rootfs）
# 产物：一个已配置好 Kubuntu 桌面环境的 rootfs
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# ---- APT 源 ----
cat > /etc/apt/sources.list <<'EOF'
deb http://ports.ubuntu.com/ubuntu-ports/ noble main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ noble-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ noble-backports main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports/ noble-security main restricted universe multiverse
EOF

apt-get update
apt-get -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" upgrade

# ---- 基础工具 ----
apt-get install -y dialog locales sudo zstd

# ---- locale / 时区 ----
sed -i 's/^# *zh_CN.UTF-8/zh_CN.UTF-8/' /etc/locale.gen
grep -q '^zh_CN.UTF-8' /etc/locale.gen || echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
grep -q '^en_US.UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
cat > /etc/default/locale <<'EOF'
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh:en_US:en
EOF
echo 'Asia/Shanghai' > /etc/timezone
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# ---- 用户（小小容器约定：tiny 用户 uid=1000，免密 sudo）----
useradd -m -s /bin/bash -u 1000 tiny
echo 'tiny:tiny' | chpasswd
echo 'root:tiny' | chpasswd
echo 'tiny ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers
chmod 0440 /etc/sudoers

mkdir -p /etc/polkit-1/rules.d/
cat > /etc/polkit-1/rules.d/99-allow-all.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if (subject.user == "tiny") {
        return polkit.Result.YES;
    }
});
EOF

# ---- DNS（容器导入后使用自己的 resolv.conf）----
printf 'nameserver 223.5.5.5\nnameserver 119.29.29.29\nnameserver 8.8.8.8\n' > /etc/resolv.conf

# ---- KDE Plasma 桌面 + 图形/音频基础设施 ----
apt-get install -y \
  dbus-x11 \
  kde-plasma-desktop \
  tigervnc-standalone-server \
  x11-xserver-utils xterm \
  fastfetch wget curl nano \
  fcitx5 fcitx5-chinese-addons fonts-noto-cjk language-pack-zh-hans \
  falkon ark gwenview kate okular kwrite

# pipewire 音频（不同 Ubuntu 版本包名略有差异，逐个尝试）
apt-get install -y pipewire wireplumber || true
apt-get install -y pipewire-pulse || apt-get install -y pipewire-audio || true

# ---- 清理 ----
apt-get autoremove -y --purge
apt-get clean
rm -rf /var/lib/apt/lists/*

# ---- 校验关键文件 ----
test -x /usr/bin/startplasma-x11
test -x /usr/bin/Xtigervnc
test -d /home/tiny

echo "BUILD_OK"
