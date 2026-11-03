# Lattice

**My personal workspace and window navigation plugin for Noctalia and Umbriel.**

I created Lattice for my own desktop workflow. It displays Umbriel workspaces as compact horizontal capsules and lets me navigate between workspaces and select individual windows directly from the Noctalia bar. The idea was inspired by [Omarchy Spaces](https://github.com/tornikegomareli/omarchy-spaces), but Lattice has its own Noctalia and Umbriel implementation.

> **Personal project:** I'm sharing Lattice publicly for transparency, reference, and to showcase the ideas behind it. It is not intended as a general-purpose release or supported community plugin. I don't currently plan to provide installation assistance, setup guidance, or user support.

## What it does

- **Workspace capsules:** Display workspace labels, order, IDs, occupancy, and output ownership. Names are preserved exactly, including Unicode and numeric-looking names.
- **Active and hover states:** Follow compositor-confirmed active workspace state, with subtle hover highlights and urgency highlighting taking priority.
- **Individual window icons:** Give each window its own selectable icon, even when multiple windows use the same application. Selecting an icon validates the current stable window ID and asks Umbriel to focus that window and warp the cursor to its native target position.
- **Stable ordering and grouping:** Preserve the relative order of surviving window icons. Icons for the same application are grouped without combining their individual click targets.
- **Overflow paging:** Use `+N` to page through additional window icons when they do not fit.
- **Native tooltips:** Use Noctalia's tooltip timing and rendering, with the application ID and available window title supplied by Lattice.
- **Output-aware behavior:** Check workspace and window interactions against their current output and state.

Clicking a workspace label navigates to that workspace. Hovering does not navigate or focus a window.

## Requirements

- Noctalia with plugin API support through **API 43**.
- Umbriel with workspace, window, output, and native action IPC.
- Python 3 for the read-only IPC reader and one-shot action helper. Both use the Python standard library.

I designed Lattice for Noctalia running with Umbriel. It does not provide an integration for other compositors.

## How it works

- `service.luau` owns the Noctalia service lifecycle and publishes normalized state.
- `ipc_reader.py` subscribes to Umbriel IPC and forwards full workspace, window, and output snapshots.
- `lib/state.luau` reduces snapshots while retaining stable IDs, global focus, and workspace-local focus.
- `bar.luau` and the inline model/UI modules build the capsules, icons, and paging controls for each bar output.
- `lib/interaction.luau` validates references before dispatch. `action_request.py` makes bounded, read-only inventory checks before sending a workspace-switch or exact-window focus-and-warp action.

The production dependency allowlist is recorded in [`PRODUCTION_FILES.sha256`](PRODUCTION_FILES.sha256). Historical reports, evidence, and prototypes are not runtime dependencies.

## Current limitations

- Lattice does not capture live window thumbnails.
- Lattice cannot move a window to another workspace by exact window ID. Umbriel needs an atomic exact-ID move action before safe window movement can be supported.
- Workspace switching uses Umbriel's name or positional selector; a final reorder race cannot be fully eliminated by the current interface.
- The workspace model keeps outputs independent, but physical multi-monitor and hotplug behavior have not been verified in the recorded live test.
- Very long workspace labels may exceed the space available in the host bar; Lattice does not rewrite them.

## Development & transparency

I developed Lattice with substantial assistance from AI tools through an iterative process.

I used AI tools to help explore ideas, generate and refine code, investigate issues, and improve the implementation. I reviewed changes and worked through repeated rounds of testing, debugging, and refinement rather than treating generated code as automatically correct.

The repository includes automated tests and validation checks. These help catch regressions and verify parts of the implementation, but they do not prove that every behavior is bug-free or that every environment has been tested. Some limitations and unverified behaviors are listed above.

## Development checks

From the repository root, I use:

```sh
python3 -B tests/run.py
noctalia plugins lint .
python3 -B tools/verify_api.py
sha256sum -c PRODUCTION_FILES.sha256
```

The API checker verifies a specific previously audited Noctalia binary. If that binary changes, the checker asks for a new compatibility audit. The maintained test runner uses synthetic fixtures and temporary sockets; it does not exercise a user's live Umbriel session.

## License

Lattice is released under the [MIT License](LICENSE).
