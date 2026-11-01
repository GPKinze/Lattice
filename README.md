# Lattice

Lattice is a Noctalia bar plugin for navigating Umbriel workspaces and windows. It shows Umbriel's workspaces as compact horizontal capsules and lets me select individual windows from the bar. The idea was inspired by [Omarchy Spaces](https://github.com/tornikegomareli/omarchy-spaces); Lattice has its own Noctalia and Umbriel implementation.

## What it does

- **Workspace capsules:** labels, order, IDs, occupancy, and output ownership come from Umbriel. Lattice preserves names exactly, including Unicode and numeric-looking names.
- **Active and hover states:** the active workspace follows compositor-confirmed state. Hover highlights are subtle, and urgency highlighting takes priority.
- **Individual window icons:** each window has its own selectable icon, even when several windows use the same application. Clicking an icon validates the current stable window ID and asks Umbriel to focus that exact window and warp the cursor to its native target position.
- **Stable ordering and grouping:** surviving window icons keep their relative order as state changes. Icons for the same application are grouped together without combining their individual click targets.
- **Overflow paging:** when a workspace has more windows than fit, `+N` pages through the remaining icons.
- **Native tooltips:** Noctalia supplies tooltip timing and rendering; Lattice provides the application ID and available window title.
- **Output-aware behavior:** workspace and window interactions are checked against their current output and state.

Clicking a workspace label navigates to that workspace. Hovering does not navigate or focus a window.

## Requirements

- Noctalia with plugin API support through **API 43**.
- Umbriel with its workspace, window, output, and native action IPC.
- Python 3 for the read-only IPC reader and one-shot action helper. Both use the Python standard library.

Lattice is designed for Noctalia running with Umbriel. It does not provide an integration for other compositors.

## How it works

- `service.luau` owns the Noctalia service lifecycle and publishes normalized state.
- `ipc_reader.py` subscribes to Umbriel IPC and forwards full workspace, window, and output snapshots.
- `lib/state.luau` reduces snapshots while retaining stable IDs, global focus, and workspace-local focus.
- `bar.luau` and the inline model/UI modules build the capsules, icons, and paging controls for each bar output.
- `lib/interaction.luau` validates references before dispatch. `action_request.py` makes bounded, read-only inventory checks before sending a workspace-switch or exact-window focus-and-warp action.

The production dependency allowlist is recorded in [`PRODUCTION_FILES.sha256`](PRODUCTION_FILES.sha256). Historical reports, evidence, and prototypes are not runtime dependencies.

## Current limits

Lattice does not capture live window thumbnails and cannot move a window to another workspace by exact window ID. Umbriel needs an atomic exact-ID move action before safe window movement can be supported. Workspace switching uses Umbriel's name or positional selector; a final reorder race cannot be fully eliminated by the current interface.

The workspace model keeps outputs independent, but physical multi-monitor and hotplug behavior have not been verified in the recorded live test. Very long workspace labels may exceed the space available in the host bar; Lattice does not rewrite them.

## Installation

There is no general-purpose install script. Use the plugin installation workflow documented for your Noctalia version, with this repository's `plugin.toml` as the manifest. Enable Lattice through Noctalia and add its bar widget using the shell's plugin and bar controls. The host desktop controls the overall bar layout.

Lattice does not require a fixed overall bar width or end margins. These are controlled by the host desktop layout.

See the [Noctalia plugin documentation](https://github.com/noctalia-dev/noctalia/tree/v5.4.0/docs/user/plugins) for the versioned plugin workflow.

## Development

From the repository root:

```sh
python3 -B tests/run.py
noctalia plugins lint .
python3 -B tools/verify_api.py
sha256sum -c PRODUCTION_FILES.sha256
```

The API checker verifies a specific previously audited Noctalia binary. If that binary changes, the checker asks for a new compatibility audit. The maintained test runner uses synthetic fixtures and temporary sockets; it does not exercise a user's live Umbriel session.

## License

Lattice is released under the [MIT License](LICENSE).
