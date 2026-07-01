# OpenWrt 设备配置规范 (device.yaml Schema)

每个设备目录（如 `devices/mt3600be/`）下必须包含一个 `device.yaml` 文件，用于声明设备的编译目标、包列表、镜像参数与构建源信息。

---

## 字段详解

### 1. 硬件身份字段 (必填)

确定 OpenWrt 构建系统的目标架构与配置文件。

```yaml
# 设备唯一标识符，通常与目录名一致
name: mt3600be
# OpenWrt Target (例如: mediatek, x86, armsr)
target: mediatek
# OpenWrt Subtarget (例如: filogic, 64, armv8)
subtarget: filogic
# OpenWrt Profile (例如: glinet_gl-mt3600be, generic)
profile: glinet_gl-mt3600be
# 架构标识符，用于匹配 APK 仓库目录结构
arch: aarch64_cortex-a53
```

---

### 2. 构建源 (`source`)

声明 OpenWrt 基础 SDK / ImageBuilder 的获取方式。

```yaml
source:
  # R2 存储桶中的目录通道名称（如 snapshot, openwrt-25.12）
  channel: snapshot
  # 获取模式：download（官方直下）或 build（自编译拉取）
  mode: download

  # ── 通用必填：官方上游源根地址（UPSTREAM_BASE）──
  # download 模式：由此直下官方 SDK/IB 与包；build 模式：由此借取 L3 社区 feed。
  # 脚本会在其后拼接 /targets/<target>/<subtarget>/ 等路径，须严格遵守 OpenWrt 官方目录结构；
  # 指向 release 时请写完整 patch（如 .../releases/25.12.5），系统不再猜测 patch 号。
  upstream: https://downloads.openwrt.org/snapshots

  # ── 当 mode: build 时必填 ──
  # repo: https://github.com/openwrt/openwrt
  # ref: main # 分支或 tag 均可（如 v25.12.5）

  # 驱动获取模式解耦（可选）：默认继承 mode 的值
  # kmod_source: download # 若填 download，即使自编 IB 组装固件也会去官方拉取内核驱动
```

---

### 3. 软件包配置 (`packages`)

控制固件中预装或移除的软件包。所有设备还会自动继承 `devices/_common/common.yaml` 中的基础包列表。

```yaml
packages:
  # 追加安装的软件包列表
  add:
    - luci
    - sing-box
  # 显式移除的软件包（如 OpenWrt 默认附带的冲突包）
  remove:
    - dnsmasq
    - wpad-basic
```

---

### 4. 外部软件源 (`repos`)

指定在构建与运行时加入的额外 APK 仓库地址。

```yaml
# 额外 APK 仓库 URL 列表
repos:
  # - https://example.com/openwrt/packages
```

---

### 5. 镜像定制 (`image`)

配置生成镜像的分区与参数。

```yaml
image:
  # RootFS 分区大小（单位：MiB）。填 0 则使用 ImageBuilder 默认值
  rootfs_partsize: 256
```

---

## 完整配置示例

```yaml
name: mt3600be
target: mediatek
subtarget: filogic
profile: glinet_gl-mt3600be
arch: aarch64_cortex-a53

source:
  channel: snapshot
  mode: download
  upstream: https://downloads.openwrt.org/snapshots

packages:
  add:
    - luci
    - sing-box
  remove:
    - dnsmasq
    - wpad-basic

repos: []

image:
  rootfs_partsize: 256
```
