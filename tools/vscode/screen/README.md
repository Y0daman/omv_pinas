# OMV PiNAS Screen Preview (VS Code)

Local VS Code extension to preview the Freenove dashboard layout with sample values.

No Raspberry Pi is required for mock mode.

## Features

- Open a local screen preview panel
- Portrait/Landscape toggle
- WiFi/LAN status toggle
- Live mock metrics update
- Optional live mode using a noVNC URL

## Run Locally

1. Open this folder in VS Code:
   - `tools/vscode/screen`
2. Press `F5` to launch an Extension Development Host.
3. In the new window, run command:
   - `OMV PiNAS: Open Screen Preview`
   - `OMV PiNAS: Open Live noVNC Preview` (optional)

## Live noVNC Mode

Set default URL in VS Code settings:

- `omvPinasScreen.novncUrl` (default: `http://127.0.0.1:6080/vnc.html`)

You can also open live mode from the Activity Bar view (`Pi Screen`).

## Build VSIX

From `tools/vscode/screen`:

```bash
chmod +x build-vsix.sh
./build-vsix.sh
```

Or manually:

```bash
npm install
npm run build:vsix
```

Install the generated `.vsix` in VS Code:

```bash
code --install-extension omv-pinas-screen-preview-0.0.9.vsix
```

## Notes

- This is a design-time preview only.
- It does not read real metrics from the Pi.
