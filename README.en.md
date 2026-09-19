# OpenCode TUI for fnOS

Bring **OpenCode**'s official TUI to your fnOS NAS — click the desktop icon and start using it.

| | |
| :--- | :--- |
| **Developer** | [anomalyco](https://github.com/anomalyco/opencode) (OpenCode) |
| **Publisher** | [techysy](https://github.com/techysy/opencode-fnos) (fnOS packaging) |

> This project only **packages and adapts** OpenCode for fnOS. The engine is built from
> the official source with 3 minimal adaptation patches applied.
> Upstream: <https://github.com/anomalyco/opencode>

[![Release](https://img.shields.io/github/v/release/techysy/opencode-fnos.svg?label=Latest&color=blue)](https://github.com/techysy/opencode-fnos/releases)
[![Downloads](https://img.shields.io/github/downloads/techysy/opencode-fnos/total?label=Downloads&color=green)](https://github.com/techysy/opencode-fnos/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Upstream](https://img.shields.io/github/v/release/anomalyco/opencode.svg?label=Upstream&color=purple)](https://github.com/anomalyco/opencode/releases)

- [中文文档](./README.md)

---

## 📥 Download

**➡️ [Get the latest release on GitHub](https://github.com/techysy/opencode-fnos/releases/latest)**

Pick the package matching your NAS CPU architecture:

| Arch | File | Devices |
| :--- | :--- | :--- |
| x86_64 | `opencode-tui-<version>-x86.fpk` | Most Intel / AMD models |
| arm64 | `opencode-tui-<version>-arm.fpk` | ARM models |

> Current: **v1.18.31** — bundles the official OpenCode v1.18.31 engine

---

## What is this

[OpenCode](https://github.com/anomalyco/opencode) is an open-source AI coding assistant
(terminal TUI + Web UI).

This project packages the **official unmodified TUI** as a fnOS app:

- **Engine**: official OpenCode v1.18.31 (built from official source)
- **UI**: the official TUI, wrapped as a web terminal by [ttyd](https://github.com/tsl0922/ttyd)
- **Entry**: fnOS desktop icon / browser

**No UI was rewritten** — what you see is the official TUI itself.

## Features

| Feature | Description |
| :--- | :--- |
| ✅ Official TUI | Uses the official `opencode` binary |
| ✅ Desktop integration | One-click icon, embedded via iframe |
| ✅ Data isolation | Dedicated user `opencode-tui`, data in `/vol4/@appdata/opencode-tui/` |
| ✅ XDG isolation | config/data/cache/state all inside the app data dir |
| ✅ Coexists with others | Own appname, port 19282 |
| ✅ Clipboard fix | Fixes ttyd copy inside iframes |
| ✅ Branded | OpenCode icon + fixed page title |
| ✅ No hardcoded volumes | Data dir is derived at runtime |

## Install

1. Download the `.fpk` for your architecture
2. fnOS → **App Center** → top-right **Manual Install** → pick the `.fpk`
3. Accept the license in the install wizard to finish

Then click **OpenCode TUI** on the fnOS desktop.

> `appname` is `opencode-tui`, so it does not conflict with other versions.

## Usage

Configure model credentials on first run:

```bash
opencode providers
```

The default workspace is `/vol4/@appdata/opencode-tui/workspace`. Point it at your own repo:

```bash
export OPENCODE_WORKSPACE=/vol1/1000/your-project
```

## Build

```bash
# Full build (fetch source → patch → install deps → compile engine → pack)
bash scripts/build.sh --from-source

# Pack only (when app/bin/opencode already exists)
bash scripts/build.sh

# arm64
ARCH=arm bash scripts/build.sh --from-source
```

> Requires `fnpack` >= 1.2.4, `bun` >= 1.3.0, `patch`, `curl`, `node`

## Tracking upstream

```bash
bash scripts/check-upstream.sh          # check for a new release
bash scripts/check-upstream.sh --apply  # bump VERSION + manifest
git commit -am "chore: bump upstream to vX.Y.Z"
git tag vX.Y.Z && git push origin master --tags
```

You can also run **Actions → Build OpenCode TUI fpk → Run workflow** manually.

## Changes to upstream

Only **minimal adaptations** are applied
(see [`docs/patches/fnos-adaptation.patch`](docs/patches/fnos-adaptation.patch)):

| File | Change | Reason |
| :--- | :--- | :--- |
| `packages/script/src/index.ts` | Relax bun version to `>=1.3.0` | Build env compatibility |
| `server/shared/ui.ts` | CSP adds `frame-ancestors *` and `ws:`/`wss:` | iframe + WebSocket |
| `server/shared/public-ui.ts` | Static assets bypass auth | Page loads inside iframe |

**Engine logic itself is untouched.**

## Disclaimer

- This is an **unofficial third-party adaptation**, not affiliated with the OpenCode team
- OpenCode is MIT licensed; copyright belongs to its original authors
- The engine binary is built from official source with only the minimal patches above

## License

[MIT](LICENSE) — original OpenCode copyright notices retained
