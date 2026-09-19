# CHANGELOG / 更新日志

本项目版本号**跟随上游 OpenCode 官方版本**。

---

## v1.18.31 (2026-09-20)

首个飞牛（fnOS）发布版，对应官方 OpenCode **v1.18.31**。

### ✨ 功能

- 🖥️ **官方原版 TUI**：直接使用官方 `opencode` 二进制的 TUI（终端界面），**未重制界面**
- 🌐 **网页终端接入**：通过 ttyd 1.7.7 把 TUI 包装为网页终端，飞牛桌面 iframe 内直接使用
- 🖱️ **飞牛桌面集成**：桌面图标一键打开，`appname=opencode-tui`
- 🔒 **数据隔离**：独立系统用户 `opencode-tui`，数据存于 `/vol4/@appdata/opencode-tui/`
- 🗂️ **XDG 目录隔离**：`XDG_DATA_HOME` / `XDG_CONFIG_HOME` / `XDG_CACHE_HOME` / `XDG_STATE_HOME`
  全部指向应用数据目录，避免写入 NAS 上不可写的 `$HOME/.local/share`
- 🤝 **可与其他版本共存**：`appname=opencode-tui`，端口 **19282**，与 mimocode(19280/19281) 互不冲突
- 📜 **安装协议授权向导**：首次安装需勾选同意 7 项条款（非官方/版权/担保/风险/权限/网络/许可）
- 🎨 **品牌化**：OpenCode 图标（64/128/256 三档）+ 固定页面标题 `OpenCode`
- 🧭 **不写死卷路径**：`cmd/_lib.sh` 自动推导数据目录，兼容不同 fnOS 部署布局

### 🐛 修复

- 📋 **修复 iframe 内复制失效**：ttyd 原仅用 `document.execCommand('copy')`，
  在飞牛桌面 iframe 中静默失败。现改为三级降级链：
  1. `navigator.clipboard.writeText()`
  2. 隐藏 textarea + `execCommand('copy')`
  3. 提示用户手动选择
  并在有 xterm 选区时拦截 Ctrl/Cmd+C（无选区则不拦截，保留 SIGINT 语义）
- 🖱️ **右键复制**：有选区时右键直接复制，规避不安全上下文下浏览器菜单失效
- 🖼️ **iframe 布局**：内嵌时去掉多余内边距，避免出现双滚动条

### 🔧 对上游的最小适配（3 处）

见 [`docs/patches/fnos-adaptation.patch`](docs/patches/fnos-adaptation.patch)：

| 文件 | 改动 | 原因 |
| :--- | :--- | :--- |
| `packages/script/src/index.ts` | 放宽 bun 版本约束为 `>=1.3.0` | 兼容构建环境的 bun 版本 |
| `packages/opencode/src/server/shared/ui.ts` | CSP 增加 `frame-ancestors *` 与 `ws:`/`wss:` | 支持 iframe 嵌入与 WebSocket |
| `packages/opencode/src/server/shared/public-ui.ts` | 静态资源免鉴权 | 页面在 iframe 中能正常加载 |

**引擎逻辑本身未做任何修改。**

### 📦 产物

| 架构 | 文件 |
| :--- | :--- |
| x86_64 | `opencode-tui-1.18.31-x86.fpk` |
