# tiny-container-kubuntu

为 **小小容器（Tiny Container）** 构建的 **Kubuntu 24.04 LTS（KDE Plasma，arm64）** 容器镜像。

官方容器基于 Debian + Xfce，本仓库通过 GitHub Actions 构建一个 Ubuntu 24.04 (noble) + KDE Plasma 的替代容器，并完整适配小小容器的导入格式（`/.tiny.yaml` + proot 启动命令 + `/opt/tiny` 辅助文件）。

## 镜像内容

| 项目 | 说明 |
|---|---|
| 基础系统 | Ubuntu 24.04 LTS (noble) arm64 |
| 桌面 | `kde-plasma-desktop`（Plasma X11 会话，`startplasma-x11`） |
| 图形前端 | TigerVNC（AVNC）+ Termux:X11 均可用 |
| 音频 | PipeWire + WirePlumber（配置复用官方容器） |
| 中文支持 | `zh_CN.UTF-8` locale、Noto CJK 字体、fcitx5 + 中文输入法 |
| 浏览器/应用 | Falkon、Ark、Gwenview、Kate、Okular、Konsole、Dolphin 等 |
| 默认账户 | 用户 `tiny`（密码 `tiny`，免密 sudo）；root 密码 `tiny` |
| 时区/区域 | Asia/Shanghai / zh_CN.UTF-8 |

## 使用方法

1. 到本仓库 [Releases](../../releases) 下载 `kubuntu-zh-*.tar.zst`
   - 若为分卷文件（`*.tar.zst.part-00`、`*.part-01`…），先合并：
     ```bash
     cat kubuntu-zh-*.tar.zst.part-* > kubuntu-zh.tar.zst
     ```
2. 打开小小容器，在主界面点击 **导入** 按钮，选择该文件
3. 导入完成后进入「功能」页，启用 **X11 (Termux:X11)** 或 **AVNC (VNC)** 图形前端
4. 重启容器，即可进入 KDE Plasma 桌面

> 注意：KDE Plasma 比 Xfce 重，在手机 proot 环境下建议至少 6GB 内存的设备，首次进入桌面会较慢。

## 构建原理

构建完全在 GitHub Actions 上进行（`.github/workflows/build.yml`），也可手动触发（workflow_dispatch）：

1. **bootstrap**：在 x86_64 runner 上用 `debootstrap --arch=arm64 --foreign` 拉取 Ubuntu noble arm64 基础系统，再通过 `qemu-user-static` 完成 second-stage
2. **build.sh**（在 qemu chroot 内执行）：配置 APT 源、locale、时区、`tiny` 用户（uid 1000、免密 sudo、polkit 放行）、安装 KDE Plasma 与音频/中文支持，并清理缓存
3. **assemble.sh**（runner 上执行）：
   - 下载官方 `trixie-zh` 容器，抽取 `/opt/tiny` 辅助文件、伪造 `/proc` 信息文件（`.loadavg` 等）、`/sys/.empty`、pipewire/wireplumber 配置
   - 用官方 `.tiny.yaml` 改写：`code`/`name`/`description` 换为 Kubuntu，图形会话命令 `startxfce4` → `startplasma-x11`
   - 打包：`.tiny.yaml` 必须是 tar 归档**第一个成员**（软件靠它快速识别容器），随后整体 zstd 压缩；超过 2GB 自动分卷
4. **发布**：成品自动发布到 Releases（单文件上限 2GB）

## 本地触发构建

推送对 `build.yml` / `build.sh` / `assemble.sh` 的修改即自动触发；也可在 Actions 页面手动 **Run workflow**。

## 已知限制

- **性能**：proot 用户态方案 + qemu 交叉构建，运行性能是正常 proot 水平；Plasma 桌面比 Xfce 占用更高
- **音频**：pipewire 配置来自 Debian trixie，与 Ubuntu noble 的 pipewire 版本可能有差异，若无声可在容器内重装 `pipewire` 系列包
- **浏览器**：Ubuntu 的 Firefox/Chromium 均为 snap，proot 下不可用，因此预装 deb 版的 Falkon
- **Wayland/GNOME/systemd**：小小容器明确不支持，本镜像同样不涉及
