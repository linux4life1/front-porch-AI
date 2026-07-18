# Installation Guide

Front Porch AI runs on Windows, macOS, and Linux. This page covers installing the app, plus build-from-source instructions for developers.

If you're wondering whether your computer can handle it, see [What You Need to Run It](getting-started.md#what-you-need-to-run-it) in the Getting Started guide — the short answer is that most machines from the last several years are fine, and a graphics card is helpful but optional.

---

## Table of Contents

- [Windows](#windows)
- [macOS](#macos)
- [Linux — Package Managers (Recommended)](#linux--package-managers-recommended)
- [Linux — AppImage and Manual Packages](#linux--appimage-and-manual-packages)
- [Beta and Nightly Builds](#beta-and-nightly-builds)
- [After Installing](#after-installing)
- [Common Install Problems](#common-install-problems)
- [For Developers: Building from Source](#for-developers-building-from-source)

---

## Windows

1. Download the latest `.exe` installer from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases).
2. Run it and follow the prompts.
3. Launch Front Porch AI from the Start menu.

Beta builds also come as standalone `.zip` files — just extract and run, no installer needed.

## macOS

1. Download the `.pkg` installer from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases) — it's the recommended way to install on a Mac.
2. Double-click it and follow the installer. It places **Front Porch AI** in your **Applications** folder for you.
3. Launch it from Applications.

> **Tip:** Front Porch AI is code-signed and **notarized by Apple**, so macOS opens it without Gatekeeper warnings, "damaged app" scares, or right-click workarounds — on the first launch and every launch. Very few apps in this space go through notarization; we do it for every release.

A `.dmg` is also published for people who prefer drag-and-drop installs, but the `.pkg` is the smoother path and the one we recommend.

The app is built natively for Apple Silicon (M1 and newer), where it runs local AI models beautifully. It also runs on Intel Macs, but those can't handle local models — the app will guide you into remote-API mode instead.

## Linux — Package Managers (Recommended)

Installing through a package repository means updates arrive with your normal system updates (`apt upgrade`, `dnf upgrade`, `yay -Syu`).

**Debian / Ubuntu / Mint / Pop!_OS**

The quick way:
```bash
curl -fsSL https://apt.frontporchai.app/install.sh | bash
sudo apt install front-porch-ai
```

Or set the repository up by hand:
```bash
curl -fsSL https://apt.frontporchai.app/front-porch-ai.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/front-porch-ai.gpg
echo "deb [signed-by=/etc/apt/keyrings/front-porch-ai.gpg] https://apt.frontporchai.app stable main" | sudo tee /etc/apt/sources.list.d/front-porch-ai.list
sudo apt update && sudo apt install front-porch-ai
```

**Fedora / RHEL / openSUSE**

```bash
sudo dnf config-manager --add-repo https://rpm.frontporchai.app/front-porch-ai.repo
sudo dnf install front-porch-ai
```

**Arch Linux (AUR)**

```bash
yay -S front-porch-ai-bin        # stable (recommended)
yay -S front-porch-ai-beta-bin   # beta / early access
```

## Linux — AppImage and Manual Packages

Prefer no repository? The [Releases page](https://github.com/linux4life1/front-porch-AI/releases) has:

- **`.AppImage`** — download, make it executable (`chmod +x Front_Porch_AI.AppImage`), and run. All dependencies are bundled, including the web engine used for the built-in character browser.
- **`.deb`** and **`.rpm`** packages for direct installation.

---

## Beta and Nightly Builds

Two ways to get new features early:

- **Beta builds** — preview releases cut while a new version is being stabilized.
- **Nightly builds** — fresh builds of the newest development work, published most days. This is where brand-new features (like The Stoop community hub) appear first.

Both are completely isolated from your stable install: they keep their data in a separate `FrontPorchAI-Beta` folder and separate settings, so they will never touch your main characters and chats. You can run them side by side with the stable app.

Expect occasional rough edges — that's the deal with early builds. Bug reports on [Discord](https://discord.gg/e4tET6rpdv) are always welcome.

---

## After Installing

There's no manual setup. On first launch the app:

1. Downloads its AI engine (KoboldCpp) automatically, matched to your hardware.
2. Detects your graphics card and memory, and picks sensible defaults.
3. Drops you on the home screen, ready to add characters and models.

From there, open **Manage Models** in the sidebar to download your first AI model — see [Getting Started](getting-started.md#powering-the-ai-local-or-remote) for advice on picking one.

Voice features (text-to-speech and voice input) are bundled with official builds — nothing extra to install.

---

## Common Install Problems

- **AMD graphics on Linux:** if the app can't see your GPU, make sure your user account is in the `render` and `video` groups, then log out and back in.
- **Character browser won't open (Linux):** the built-in Chub.ai browser needs the WPE WebKit engine. It's bundled in the AppImage; on manual installs, install your distro's `wpewebkit` package.
- **UI flicker on Linux (Wayland):** try launching with `GDK_BACKEND=x11`.
- **Anything else:** the [Troubleshooting guide](troubleshooting.md) covers a lot more, and [Discord](https://discord.gg/e4tET6rpdv) is there for the rest.

---

## For Developers: Building from Source

Everything below is for people who want to hack on the app. Regular users can stop reading here. 🙂

**Prerequisites**

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.10.8 or later
- [Rust toolchain](https://rustup.rs/) — builds the memory (RAG) embedding server
- Python 3.8+ — only needed to run the voice sidecars in dev mode
- Git

**Linux build dependencies**

Ubuntu/Debian:
```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libwpewebkit-1.0-dev
```

Fedora:
```bash
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel wpewebkit-devel
```

Arch:
```bash
sudo pacman -S clang cmake ninja pkgconf gtk3 xz wpewebkit
```

**Clone and run**

```bash
git clone https://github.com/linux4life1/front-porch-AI.git
cd front-porch-AI
flutter pub get
flutter run
```

**Release builds**

```bash
# The embedding server (needed for memory/RAG)
cargo build --release --manifest-path tools/embed_server/Cargo.toml

# Then the app
flutter build windows   # or: flutter build linux
./scripts/build-macos.sh   # macOS — bundles the embedding server for you
```

On Windows and Linux, copy the built `embed_server` binary next to the app executable (under `embed_server/`) so memory features work.

**Voice features in dev mode** run through Python directly, so install their packages:

```bash
pip install kokoro-onnx soundfile faster-whisper
```

(Official release builds bundle these — end users never need Python.)

---

*Questions? Join the [Discord](https://discord.gg/e4tET6rpdv) — I'm happy to help.*
