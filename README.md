# SPACE


<p align="center">
  <img src="SPACE/Assets/icon-square.png" width="160" alt="SPACE app icon">
</p>

SPACE is a lightweight and efficient macOS app that overrides the system animation for desktop switching and removes the useless animation time. On regular macOS this animation is sluggish and slow on high refresh rate monitors. This app is here to fix it.

## Features

- **Instant switching** — replaces the default animated transition with an immediate space change
- **Native shortcuts** — uses the standard Control + arrow key bindings
- **Lightweight** — background menu bar app with minimal resource usage
- **No SIP changes** — uses public Accessibility APIs only
- **Gesture Support with trackpad** - replaces animated transition
- **Faster Animation Support** - speeds up default animations.
## Install

### Option 1: Download the DMG (recommended)

1. Download `SPACE.dmg` from [Releases](https://github.com/YOUR_USERNAME/SPACE/releases)
2. Open the DMG
3. Drag **SPACE** into **Applications**
4. Launch SPACE from Applications
5. Grant **Accessibility** permission when prompted

### Option 2: Build from source

```bash
git clone https://github.com/YOUR_USERNAME/SPACE.git
cd SPACE
make dmg
open dist/SPACE.dmg
```

## Usage

Once running, SPACE lives in your menu bar. Use:

| Shortcut | Action |
|----------|--------|
| `Ctrl + ←` | Previous Space |
| `Ctrl + →` | Next Space |

Quit via the menu bar icon → **Quit SPACE**.

## Permissions

SPACE requires **Accessibility** access to intercept keyboard shortcuts before macOS handles them.

**System Settings → Privacy & Security → Accessibility → enable SPACE**


MIT — see [LICENSE](LICENSE).
