<div align="center">

# 🪟 NameLess UI

**A glass desktop shell for Hyprland and driftwm, built on Quickshell**

`Quickshell` · `QML` · `Hyprland` · `driftwm` · `PipeWire`

[🇷🇺 Русский](README.md) · 🇬🇧 English

[Features](#-features) · [Install](#-installation) · [Setup](#-setup) · [IPC](#-ipc-commands) · [Languages](#-languages) · [Layout](#-layout)

</div>

---

## ✨ Features

| | |
|---|---|
| 📊 **Bar** | workspaces, clock, player, tray, network, sound, battery; **adapts to the screen width** — full on a normal monitor, trimmed on a medium one, icons only on a narrow one (a phone as a second monitor) |
| 🧰 **Dock** | pinned and running apps, Orbit icons, widgets |
| 🚀 **Launcher** | app search and calculator; list, grid and Spotlight views |
| 🎛 **Control center** | tiles (large and small, your own order), sound, brightness, player, power, profiles; the drawer view (style, position, width, height) is shared with the appearance drawer |
| 🎨 **Appearance** (`SUPER+X`) | Classic, Liquid Glass, iOS, Aurora, EchoStar and holiday templates; palettes, accent, color from wallpaper; on a wide screen “Themes” uses three columns |
| 🖼 **Wallpaper wizard** | your folders, internet sources (Wikimedia, Bing, Wallhaven…), timed change, drag files into the window, search by name |
| 🎬 **Screen recording** | MP4 video or GIF, system / microphone / both audio, frame rate, quality, cursor, countdown; edit finished recordings |
| 📋 **Clipboard** | searchable history, pinned entries (cliphist) |
| 🔊 **Sound** | output, input, per-app volume, channel and microphone tests |
| 📈 **Task manager** | processes, load, memory, disks, network, GPU |
| 📦 **Programs** | an app catalog: install, remove, update, search repositories and AUR |
| 🧩 **Widgets** | clock, weather, calendar, notes, timer, player, Claude limits, Orbit devices |
| 🌌 **Live backgrounds** | starry sky, space (solar system), window orbits |
| 🔒 **Lock screen** | several styles, notifications, player |
| 🪐 **Orbit** | icon and device ribbon, tile, widget — link with your phone (the [NameLess Orbit](../nameless-orbit) app) |
| 🌐 **Languages** | Russian and English, chosen on first launch |

## 📦 Installation

**From the repository** (recommended): the installer saves your previous files and copies the shell.

```bash
git clone https://github.com/thecylindr/nameless-ui.git && cd nameless-ui
./install.sh                 # copies nameless and ThemeDrawer to ~/.config/quickshell (old ones go to a backup)
```

**Manually:**

```bash
mkdir -p ~/.config/quickshell
cp -r nameless ThemeDrawer ~/.config/quickshell/
qs -c nameless &             # the shell
qs -c ThemeDrawer &          # the appearance drawer
```

**Requires:** `quickshell`, Hyprland (or driftwm), PipeWire, a Nerd Font (icons). For specific parts: `cliphist` and `wl-clipboard` (clipboard), `gpu-screen-recorder` or `wf-recorder`, `slurp` and `ffmpeg` (recording), `hyprpicker` (color picker), `playerctl`, `NetworkManager`, `awww` (smooth wallpaper changes).

> **Themes.** Switching templates and palettes is done by the script `~/.config/hypr/Scripts/theme.sh`, which ships with the Hyprland config set ([NameLess UI](https://github.com/thecylindr/nameless-ui)). Without it the shell works, but the Appearance drawer cannot apply templates.

## ⚙️ Setup

- **Language** — on first launch, later: “Control center” → view icon (󰕮) → “Language”.
- **Drawer view** — the same icon: style (window or drawer), where it opens, width, tile counts; shared by Appearance and the control center.
- **Tiles and widgets** — the pencil in the control center header; “Features” shows what is on and how much load it adds.
- **Performance mode** — “Auto” switches to economy on battery (live backgrounds at 30 fps, less frequent polling).
- **Settings files**: `~/.config/glassrice/nameless.json` (dock, widgets, tiles, recording, language) and `~/.config/glassrice/drawer.json` (drawer view).

## 🎹 IPC commands

```bash
qs -c nameless ipc call control toggle        # control center
qs -c nameless ipc call wallpapers toggle     # wallpaper wizard
qs -c nameless ipc call recorder toggle       # “Screen recording” window
qs -c nameless ipc call record screen         # start/stop screen recording
qs -c nameless ipc call audio toggle          # “Sound” window
qs -c nameless ipc call orbit toggle          # Orbit device ribbon
qs -c nameless ipc call widgets edit          # edit widgets
```

## 🌐 Languages

Source texts in the code are Russian, wrapped in `Tr.t("…")`; English comes from `nameless/i18n/en.json` (“Russian string” → “English string”). A string missing from the dictionary stays Russian, so the interface never goes blank. Switching is instant. To help with translation, edit `en.json`.

## 🗂 Layout

```
nameless/              the shell itself
    shell.qml          entry point: windows are loaded lazily (Lazy)
    Bar.qml  Dock.qml  Launcher.qml  ControlCenter.qml  Wallpapers.qml  RecorderPanel.qml …
    Config.qml         settings (singleton), Tr.qml — language, Theme.qml — appearance
    i18n/en.json       English translation
ThemeDrawer/           the appearance drawer (separate process)
```

## 🧯 Troubleshooting

- Shell log: `qs -c nameless log`.
- Quickshell reloads a file as soon as it changes; QML errors appear in the log.
- Found a bug or have an idea — open an issue in the project repository.

## 📄 License

**NameLess Source-Available License 1.0** — [LICENSE](LICENSE). In short: you may read, build and use the code **for yourself, non-commercially**; a fork needs the author's written permission first (ask in an issue beforehand). You may not copy, fork without permission and publish the project (whole or in substantial parts), release derivative versions, use it commercially, pass it off as your own, or build datasets from the code to train models. Need more — contact the author via the repository. Third-party components (Qt, FFmpeg, Quickshell…) stay under their own licences.
