# Compatibility

Lattice is a native Noctalia plugin for Umbriel. It depends on Umbriel's native IPC for workspace, window, and output state, and for workspace switching and exact-window focus-and-warp actions.

## Supported target

- **Noctalia:** plugin API 43, with Python 3 available to the plugin service.
- **Umbriel:** the IPC and actions described by the upstream documentation linked below.

The last recorded controlled-session version check was **2026-11-01**: Noctalia `v5.4.0 (5.4.0-1-dirty)` and Umbriel `0.1.0` at commit `2952bbcbbb46`. The Noctalia API ceiling was independently checked against the installed binary on **2026-10-31**. These are historical verification records, not a fresh check performed while editing this document.

## Architecture and behavior

The manifest declares `plugin_api = 43` and registers one Noctalia service and one inline bar widget. The service owns a Python IPC reader. Luau state, model, and UI modules prepare per-output workspace capsules and individually selectable window icons. A one-shot Python helper validates current workspace/window/output state before requesting an action.

Workspace labels and order come from Umbriel. Clicking a workspace capsule requests a switch using Umbriel's reported name or position and output. Clicking a window icon sends its stable ID to Umbriel's `window-focus-warp` action. Umbriel resolves that exact ID, focuses it, and performs its native cursor warp; Lattice does not provide warp coordinates or change global cursor settings. If the selected target is stale, the action fails rather than substituting another window.

Lattice supports inline navigation, active/hover/urgency styling, per-window icons, same-application grouping, overflow paging, and native Noctalia tooltips. Exact-ID workspace movement, drag-and-drop, and live window thumbnails are not supported. Lattice does not implement another compositor integration.

## Verification evidence

The installed Noctalia binary checked on 2026-10-31 had SHA-256 `cee728de4f2b7cbc185f64e530a1c22a09301b58dc2914f310c30d3a99ffcd9f`. Read-only inspection of its plugin-loader compatibility check confirmed support for API versions 3 through 43. [`tools/verify_api.py`](tools/verify_api.py) checks that exact binary hash and guard; it was not rerun for this documentation update. A different binary needs a new audit.

The 2026-11-01 controlled integration recorded the running Noctalia and Umbriel versions above and exercised the production focus-and-warp interaction. Automated and isolated visual checks are described here only as evidence from that dated verification; they do not establish compatibility with later versions or every physical multi-monitor configuration. The plugin has not been freshly tested against a different Noctalia or Umbriel build as part of this documentation update.

## Upstream references

**Noctalia v5.4.0**

- [Plugin API constants](https://github.com/noctalia-dev/noctalia/blob/v5.4.0/src/scripting/plugin_api.h)
- [Plugin runtime API](https://github.com/noctalia-dev/noctalia/blob/v5.4.0/docs/user/plugins/development/runtime-api.mdx)
- [Plugin manifest and settings](https://github.com/noctalia-dev/noctalia/blob/v5.4.0/docs/user/plugins/development/manifest.mdx)
- [Declarative UI](https://github.com/noctalia-dev/noctalia/blob/v5.4.0/docs/user/plugins/development/declarative-ui.mdx)

**Umbriel 2952bbcbbb46**

- [IPC documentation](https://github.com/noctalia-dev/umbriel/blob/2952bbcbbb46/docs/user/ipc.md)
- [Workspace semantics](https://github.com/noctalia-dev/umbriel/blob/2952bbcbbb46/docs/user/workspaces.md)
- [Action documentation](https://github.com/noctalia-dev/umbriel/blob/2952bbcbbb46/docs/user/actions.md)
- [Focus-and-warp action implementation](https://github.com/noctalia-dev/umbriel/blob/2952bbcbbb46/src/server/actions.cpp#L1466-L1498)
- [Native cursor target behavior](https://github.com/noctalia-dev/umbriel/blob/2952bbcbbb46/src/input/cursor.cpp#L1233-L1269)
