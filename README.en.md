# OpenCode for fnOS

Bring **OpenCode** to your fnOS NAS — click the desktop icon and start using it.

| | |
| :--- | :--- |
| **Developer** | [anomalyco](https://github.com/anomalyco/opencode) (OpenCode) |
| **Publisher** | [techysy](https://github.com/techysy/opencode-fnos) (fnOS packaging) |

> This project only **packages and adapts** OpenCode for fnOS. The engine is built from
> the official source with **1** minimal adaptation patch applied.
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
| x86_64 | `opencode-<version>-x86.fpk` | Most Intel / AMD models |
| arm64 | `opencode-<version>-arm.fpk` | ARM models |

> Current: **v2.0.12** — bundles the official OpenCode v2.0.12 engine
>
> The filename prefix must equal the manifest `appname` (fnOS hard requirement).
> This app uses `appname = opencode`, hence the `oc-` prefix.

---

## What is this

[OpenCode](https://github.com/anomalyco/opencode) is an open-source AI coding assistant.

This project packages the **official OpenCode** as a fnOS app:

- **Engine**: official OpenCode v2.0.12 (built from official source, 1 minimal patch)
- **UI**: the **official native Web UI** (Solid.js SPA), served by the engine's built-in `opencode serve`
- **Entry**: fnOS desktop icon (iframe) / browser

**No UI was rewritten** — what you see is the official Web UI itself.

> **About v1**: v1.18.x used "TUI + ttyd web terminal", now deprecated.
> Since v2 the app uses the official native Web UI, so **ttyd is no longer needed**
> and the UI is no longer maintained by this project.

## Features

| Feature | Description |
| :--- | :--- |
| ✅ Official native Web UI | Solid.js SPA built upstream, follows upstream automatically |
| ✅ Desktop integration | One-click icon, embedded via iframe (cross-origin + auth handled) |
| ✅ Data isolation | Dedicated user `oc`, data in `/vol4/@appdata/opencode/` |
| ✅ XDG isolation | config/data/cache/state all inside the app data dir |
| ✅ Coexists with others | Own appname (`oc`), port 19282 |
| ✅ SSE for realtime | Event stream uses Server-Sent Events (iframe/proxy friendly) |
| ✅ Branding | OpenCode icon + desktop title |
| ✅ No hardcoded volume paths | Data dir derived at runtime |

## 🌐 Short URL

The app registers the 2-letter `appname` `oc`, so it is reachable at a short URL:

```
http://opencode.techysy.fnos.net/
```

> The domain is wildcarded (`*.techysy.fnos.net`); routing is based on the
> `appname` registered with the fnOS portal.

## Install

1. Download the `.fpk` matching your architecture
2. fnOS → **App Center** → top-right **Manual Install** → choose the file
3. Accept the license → install
4. Click the **OpenCode** icon on the fnOS desktop

### CLI install

```bash
# SSH into the NAS (root required)
appcgi install /path/to/opencode-2.0.12-x86.fpk
```

---

## Usage

Then click **OpenCode** on the fnOS desktop.

### Workspace

The default workspace is `/vol4/@appdata/opencode/workspace`. To point it at your own repo:

```bash
sudo -u oc OPENCODE_WORKSPACE=/vol1/1000/my-project \
  /var/apps/opencode/cmd/main restart
```

Or edit `/var/apps/opencode/cmd/main` and change the `WORKSPACE` default.

### Service management

```bash
/var/apps/opencode/cmd/main {start|stop|status|restart}
```

---

## Upstream adaptation

Only **one** change, see [`docs/patches/fnos-adaptation.patch`](docs/patches/fnos-adaptation.patch):

| File | Change | Reason |
| :--- | :--- | :--- |
| `packages/cli/src/services/web-ui.ts` | CSP gains `frame-ancestors *` | Allow embedding via the **cross-origin** fnOS desktop iframe |

**No engine logic was modified.**

### Authentication

v2 enforces auth by default (a random password is generated if unset). The fnOS desktop
embeds via `<iframe>`, which **cannot send a Basic auth header**, therefore:

- `cmd/main` embeds a fixed password (override with `OPENCODE_PASSWORD`)
- `app/ui/config`'s `url` carries `?auth_token=<base64(opencode:password)>`

> These two must match, otherwise the page shows a **401 blank screen**. Both the build
> script and CI enforce this.

---

## Build from source

Requires **bun 1.4.2+** (v2 upstream requirement) and **fnpack 1.2.4+**.

```bash
# Build the engine from official source (fetch, patch, compile)
bash scripts/build.sh --from-source

# Package using an existing app/bin/opencode
bash scripts/build.sh

# Specific architecture
ARCH=arm bash scripts/build.sh
```

Output goes to `dist/` and is delivered to `/vol1/1000/fnOS App/fpk/opencode`.

## Upstream updates

```bash
bash scripts/check-upstream.sh            # check (looks at both releases and tags)
bash scripts/check-upstream.sh --apply    # update VERSION + manifest automatically
```

> Since v2 upstream **only pushes tags, no releases** — the script queries both.

---

## License

Unofficial packaging, released under [MIT](LICENSE).
OpenCode is copyright [anomalyco](https://github.com/anomalyco/opencode).
