# OpenCode for fnOS

把 **OpenCode** 带到飞牛 NAS（fnOS）上，直接在飞牛桌面点开就能用。

| | |
| :--- | :--- |
| **Developer** | [anomalyco](https://github.com/anomalyco/opencode) (OpenCode) |
| **Publisher** | [techysy](https://github.com/techysy/opencode-fnos) (fnOS 适配打包) |

> 本项目仅做 fnOS 平台的**适配与打包**，引擎为官方源码构建（仅 **1 处**最小适配补丁）。
> 上游：<https://github.com/anomalyco/opencode>

[![Release](https://img.shields.io/github/v/release/techysy/opencode-fnos.svg?label=Latest&color=blue)](https://github.com/techysy/opencode-fnos/releases)
[![Downloads](https://img.shields.io/github/downloads/techysy/opencode-fnos/total?label=Downloads&color=green)](https://github.com/techysy/opencode-fnos/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Upstream](https://img.shields.io/github/v/release/anomalyco/opencode.svg?label=Upstream&color=purple)](https://github.com/anomalyco/opencode/releases)

- [English](./README.en.md)

---

## 📥 下载

**➡️ [到 GitHub 下载最新版本](https://github.com/techysy/opencode-fnos/releases/latest)**

按 NAS 的 CPU 架构选择对应包：

| 架构 | 文件 | 适用设备 |
| :--- | :--- | :--- |
| x86_64 | `opencode-<版本>-x86.fpk` | 绝大多数 Intel / AMD 机型 |
| arm64 | `opencode-<版本>-arm.fpk` | ARM 机型（如部分新硬件） |

> 当前版本：**v2.0.12** — 内置官方 OpenCode v2.0.12 引擎
>
> 文件名前缀必须等于 manifest 的 `appname`（fnOS 硬性要求），本应用 `appname = opencode`，故文件名以 `oc-` 开头。

---

## 这是什么

[OpenCode](https://github.com/anomalyco/opencode) 是一个开源的 AI 编程助手。

本项目把**官方 OpenCode** 打包成飞牛应用：

- **引擎**：官方 OpenCode v2.0.12（官方源码构建，仅应用 1 处最小适配补丁）
- **界面**：**官方原生 Web UI**（Solid.js SPA），由引擎内置的 `opencode serve` 提供
- **入口**：飞牛桌面图标（iframe）/ 浏览器

**没有重写任何界面**——你看到的就是官方 Web UI 本体。

> **关于 v1**：v1.18.x 采用「TUI + ttyd 网页终端」方案，已废弃。
> v2 起改用官方原生 Web UI，**不再需要 ttyd**，界面也不再由本项目维护。

## 特性

| 特性 | 说明 |
| :--- | :--- |
| ✅ 官方原生 Web UI | Solid.js SPA，由上游构建产出，跟随上游自动升级 |
| ✅ 飞牛桌面集成 | 桌面图标一键打开，iframe 内嵌（已处理跨源与鉴权） |
| ✅ 数据隔离 | 独立用户 `oc`，数据存于 `/vol4/@appdata/opencode/` |
| ✅ XDG 全隔离 | config/data/cache/state 全部落在应用数据目录 |
| ✅ 可与其他版本共存 | appname 独立（`oc`），端口 19282 |
| ✅ 实时通道用 SSE | 事件流为 Server-Sent Events，对 iframe/反代更友好 |
| ✅ 品牌化 | OpenCode 图标 + 桌面标题 |
| ✅ 不写死卷路径 | 自动推导数据目录，兼容不同部署布局 |

## 🌐 短地址访问

应用的 `appname` 为 `oc`，因此可像 `dsh` 一样用短地址直达：

```
http://opencode.techysy.fnos.net/
```

> 域名是通配的（`*.techysy.fnos.net`），实际路由由 fnOS 门户按 `appname` 匹配。

## 安装

1. 下载对应架构的 `.fpk` 文件
2. 飞牛 → **应用中心** → 右上角 **手动安装** → 选择文件
3. 勾选同意协议 → 安装
4. 安装完成后从飞牛桌面点击 **OpenCode** 图标

### 命令行安装

```bash
# SSH 到 NAS（需 root）
appcgi install /path/to/opencode-2.0.12-x86.fpk
```

---

## 使用

安装后从飞牛桌面点击 **OpenCode** 图标即可。

### 工作目录

工作目录默认为 `/vol4/@appdata/opencode/workspace`。要指向自己的代码仓库：

```bash
sudo -u oc OPENCODE_WORKSPACE=/vol1/1000/my-project \
  /var/apps/opencode/cmd/main restart
```

或编辑 `/var/apps/opencode/cmd/main`，修改 `WORKSPACE` 默认值。

### 服务管理

```bash
/var/apps/opencode/cmd/main {start|stop|status|restart}
```

---

## 项目结构

```
.
├── manifest              # fnOS 应用元数据
├── VERSION               # 版本单一来源（跟随上游）
├── ICON.PNG              # 应用图标
├── app/
│   ├── bin/              # 引擎二进制（构建产物，不进仓库）
│   └── ui/
│       ├── config        # 桌面入口（含 auth_token）
│       └── images/       # 图标
├── cmd/                  # 生命周期脚本
│   ├── _lib.sh           # 路径推导（不写死卷路径）
│   ├── main              # start/stop/status/restart
│   ├── install_init      # 安装前检查
│   ├── install_callback  # 安装后启动服务
│   ├── upgrade_*         # 升级
│   ├── uninstall_*       # 卸载
│   └── config_*          # 配置
├── config/
│   ├── privilege         # 独立运行用户 oc
│   └── resource          # 数据共享目录声明
├── wizard/install        # 安装协议授权
├── docs/patches/         # 对上游的最小适配补丁
└── scripts/              # 构建 / 版本同步 / 上游检查
```

---

## 对上游的适配

仅有 **1 处**改动，见 [`docs/patches/fnos-adaptation.patch`](docs/patches/fnos-adaptation.patch)：

| 文件 | 改动 | 原因 |
| :--- | :--- | :--- |
| `packages/cli/src/services/web-ui.ts` | CSP 增加 `frame-ancestors *` | 允许被 fnOS 桌面**跨源 iframe** 嵌入 |

**引擎逻辑本身未做任何修改。**

### 鉴权说明

v2 默认强制鉴权（未配置也会随机生成密码）。飞牛桌面用 `<iframe>` 嵌入，
**无法发送 Basic 认证头**，因此：

- **安装向导填写密码 + 确认密码**（用户名固定 `opencode`，引擎硬编码不可改；留空自动生成）
  两次输入不一致会中止安装，不会留下半成品
- 密码保存在 `/vol4/@appdata/opencode/credentials`，可用 `OPENCODE_PASSWORD` 环境变量临时覆盖
- `app/ui/config` 的 `url` 带上 `?auth_token=<base64(opencode:密码)>`
- **会话 Cookie**：首次带 token 访问时下发 `HttpOnly` Cookie。
  因为前端加载后会把 token 从地址栏抹掉，iframe 内刷新/跳转本会丢鉴权，
  现在后续请求凭 Cookie 自动认证（这是「登录不进去」的根因）

> 安装时由 `cmd/install_callback` 自动把密码写入 `ui/config` 的 token，
> 无需手工同步。构建脚本与 CI 会强制校验整条链路完整。

---

## 从源码构建

需要 **bun 1.4.2+**（v2 上游要求）与 **fnpack 1.2.4+**。

```bash
# 从官方源码构建引擎（自动拉取 tarball、打补丁、编译）
bash scripts/build.sh --from-source

# 已有 app/bin/opencode 时直接打包
bash scripts/build.sh

# 指定架构
ARCH=arm bash scripts/build.sh
```

产物输出到 `dist/`，并按约定交付到 `/vol1/1000/fnOS App/fpk/opencode`。

## 上游更新

```bash
bash scripts/check-upstream.sh            # 检查（同时看 release 和 tag）
bash scripts/check-upstream.sh --apply    # 自动更新 VERSION + manifest
```

> 上游 v2 起**只打 tag、不建 release**，脚本已同时查询两者。

---

## 许可

本项目为**非官方**打包，遵循 [MIT](LICENSE)。
OpenCode 版权归 [anomalyco](https://github.com/anomalyco/opencode) 所有。
