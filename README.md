# OpenCode TUI for fnOS

把 **OpenCode** 的官方 TUI 带到飞牛 NAS（fnOS）上，直接在飞牛桌面点开就能用。

| | |
| :--- | :--- |
| **Developer** | [anomalyco](https://github.com/anomalyco/opencode) (OpenCode) |
| **Publisher** | [techysy](https://github.com/techysy/opencode-fnos) (fnOS 适配打包) |

> 本项目仅做 fnOS 平台的**适配与打包**，引擎为官方源码构建（仅 3 处最小适配补丁）。
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
| x86_64 | `opencode-tui-<版本>-x86.fpk` | 绝大多数 Intel / AMD 机型 |
| arm64 | `opencode-tui-<版本>-arm.fpk` | ARM 机型（如部分新硬件） |

> 当前版本：**v1.18.31** — 内置官方 OpenCode v1.18.31 引擎

---

## 这是什么

[OpenCode](https://github.com/anomalyco/opencode) 是一个开源的 AI 编程助手（终端 TUI + Web UI）。

本项目把**官方原版 TUI** 打包成飞牛应用：

- **引擎**：官方 OpenCode v1.18.31（官方源码构建，仅应用 3 处最小适配补丁）
- **界面**：官方 TUI，通过 [ttyd](https://github.com/tsl0922/ttyd) 包装成网页终端
- **入口**：飞牛桌面图标 / 浏览器访问

**没有重写任何界面**——你看到的就是官方 TUI 本体。

## 特性

| 特性 | 说明 |
| :--- | :--- |
| ✅ 官方原版 TUI | 使用官方 `opencode` 二进制，非重制界面 |
| ✅ 飞牛桌面集成 | 桌面图标一键打开，iframe 内嵌 |
| ✅ 数据隔离 | 独立用户 `opencode-tui`，数据存于 `/vol4/@appdata/opencode-tui/` |
| ✅ XDG 全隔离 | config/data/cache/state 全部落在应用数据目录 |
| ✅ 可与其他版本共存 | appname 独立，端口 19282 |
| ✅ 剪贴板修复 | 修复 ttyd 在 iframe 中复制失效的问题 |
| ✅ 品牌化 | OpenCode 图标 + 固定页面标题 |
| ✅ 不写死卷路径 | 自动推导数据目录，兼容不同部署布局 |

## 安装

1. 下载对应架构的 `.fpk`
2. 飞牛 → **应用中心** → 右上角 **手动安装** → 选择该 `.fpk`
3. 在安装向导中阅读并勾选同意协议 → 完成安装

安装后从飞牛桌面点击 **OpenCode TUI** 图标即可。

> ⚠️ 安装需知：应用的 `appname` 为 `opencode-tui`，与其它版本互不冲突，可同时安装。

## 使用

首次进入 TUI 后需要配置模型凭据：

```bash
# 在 TUI 中按提示配置
opencode providers
```

工作目录默认为 `/vol4/@appdata/opencode-tui/workspace`。要指向自己的代码仓库：

```bash
# 编辑 /var/apps/opencode-tui/cmd/main，或设置环境变量
export OPENCODE_WORKSPACE=/vol1/1000/你的项目
```

## 目录结构

```
opencode-fnos/
├── manifest              # 飞牛应用清单（版本号跟随官方）
├── VERSION               # 版本号单一来源
├── cmd/
│   ├── _lib.sh           # 路径推导（不写死卷路径）+ XDG 隔离
│   ├── main              # 生命周期脚本（start/stop/status/restart）
│   ├── install_callback  # 安装后主动拉起服务
│   ├── upgrade_callback  # 升级后重启服务
│   └── uninstall_callback
├── config/
│   ├── privilege         # 独立运行用户 opencode-tui
│   └── resource          # 数据卷权限声明
├── app/
│   ├── bin/              # opencode（引擎）+ ttyd（网关），构建时注入
│   ├── ui/               # 飞牛桌面图标与入口配置
│   └── web/index.html    # 品牌化 ttyd 页面（含剪贴板修复）
├── wizard/install        # 安装协议向导
├── docs/patches/         # 对上游的最小适配补丁
├── scripts/
│   ├── build.sh          # 打包（支持 --from-source 全量构建）
│   ├── sync-version.sh   # VERSION → manifest
│   ├── check-upstream.sh # 检查上游新版本
│   └── check-web-syntax.js # 页面 JS 语法校验（白屏防护）
└── .github/workflows/    # CI：双架构构建 + 校验 + 自动 release
```

## 自行构建

```bash
# 全量构建（下载源码 → 打补丁 → 装依赖 → 编译引擎 → 打包）
bash scripts/build.sh --from-source

# 已有 app/bin/opencode 时，仅打包
bash scripts/build.sh

# arm64
ARCH=arm bash scripts/build.sh --from-source
```

> 需要 `fnpack` ≥ 1.2.4、`bun` ≥ 1.3.0、`patch`、`curl`、`node`

## 跟进上游更新

```bash
# 1. 检查是否有新版本
bash scripts/check-upstream.sh

# 2. 有新版本时自动更新 VERSION 与 manifest
bash scripts/check-upstream.sh --apply

# 3. 提交并打 tag，CI 会自动构建并发布
git commit -am "chore: bump upstream to vX.Y.Z"
git tag vX.Y.Z
git push origin master --tags
```

也可以在 GitHub 上手动触发 **Actions → Build OpenCode TUI fpk → Run workflow**，
填写上游版本号即可（可指定仅构建某一架构）。

## 对上游的改动

本项目仅对官方源码做**最小适配**（见 [`docs/patches/fnos-adaptation.patch`](docs/patches/fnos-adaptation.patch)）：

| 文件 | 改动 | 原因 |
| :--- | :--- | :--- |
| `packages/script/src/index.ts` | 放宽 bun 版本约束（`>=1.3.0`） | 兼容构建环境的 bun 版本 |
| `packages/opencode/src/server/shared/ui.ts` | CSP 增加 `frame-ancestors *` 与 `ws:`/`wss:` | 支持 iframe 嵌入与 WebSocket |
| `packages/opencode/src/server/shared/public-ui.ts` | 静态资源免鉴权 | 页面在 iframe 中能正常加载 |

**引擎逻辑本身未做任何修改。**

## 已知问题

- **剪贴板**：已修复 iframe 内复制（多级兜底）；HTTPS 环境下体验最佳
- **HTTP 环境**：浏览器可能限制剪贴板 API，已提供 `execCommand` 兜底
- **构建耗时**：依赖安装 + Web UI 打包约需 10–30 分钟
- **端口冲突**：默认 19282，若被占用请见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)

## 安装协议授权

安装时会显示**使用协议与授权声明**，需勾选同意才能继续。条款由
[`wizard/install`](wizard/install) 定义，使用 fnOS 安装向导的 `checkbox`
必选类型实现（`required: true`，不勾选则无法安装）。

| 条款 | 内容 |
| :--- | :--- |
| **非官方声明** | 非官方第三方适配，与 OpenCode 团队无隶属、赞助或背书关系 |
| **版权归属** | OpenCode 引擎版权归原作者，遵循 MIT 协议 |
| **无担保声明** | 按「现状」提供，不附带任何担保 |
| **风险自担** | 数据丢失、服务中断、模型费用、密钥泄露等风险自负 |
| **权限说明** | 需访问 NAS 文件系统并以独立用户执行命令 |
| **网络安全** | 默认监听 19282，建议仅在内网使用，勿暴露公网 |
| **开源许可** | MIT 协议发布，保留原始版权声明 |

## 免责声明

- 本项目是**非官方的第三方适配**，与 OpenCode 开发团队无关
- OpenCode 版权归其原作者所有，遵循 MIT 协议
- 引擎二进制由官方源码构建，仅应用了上表所列最小适配补丁

## License

[MIT](LICENSE) — 保留 OpenCode 原始版权声明
