# Installation Guide

Front Porch AI runs on Windows, macOS, and Linux. This page covers installing the app, keeping it updated, and building from source if you're a developer.

If you're wondering whether your computer can handle it, see [What You Need to Run It](getting-started.md#what-you-need-to-run-it) in the Getting Started guide — the short answer is that most machines from the last several years are fine, and a graphics card is helpful but optional.

---

## Table of Contents

- [Windows](#windows)
- [macOS](#macos)
- [Linux — Package Managers (Recommended)](#linux--package-managers-recommended)
- [Linux — AppImage and Manual Packages](#linux--appimage-and-manual-packages)
- [Nightly Builds](#nightly-builds)
- [After Installing](#after-installing)
- [Common Install Problems](#common-install-problems)
- [For Developers: Building from Source](#for-developers-building-from-source)

---

## Windows

1. Download `Front_Porch_AI_Setup.exe` from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases).
2. Run it and follow the prompts.
3. Launch Front Porch AI from the Start menu.

A few things the installer quietly handles for you:

- **No admin password needed.** It installs into your own user folder, so Windows has no reason to ask for one.
- **The Visual C++ runtime** is installed automatically if your PC doesn't already have it — that's the usual culprit behind "missing VCRUNTIME140.dll" errors.
- **Channels don't collide.** Stable and nightly each install to their own folder and appear separately in Add/Remove Programs, so you can keep the stable app and try a nightly at the same time.

## macOS

Needs **macOS 13.3 Ventura** or newer (the bundled ONNX runtime is built for 13.3). Monterey and older will not run it.

1. Download `Front_Porch_AI.pkg` from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases). It's the only macOS download — there's no `.dmg` any more.
2. Double-click it and follow the installer. It places **Front Porch AI** in your **Applications** folder for you.
3. Launch it from Applications.

> **Tip:** Stable releases are code-signed and **notarized by Apple**, so macOS opens the app without Gatekeeper warnings, "damaged app" scares, or right-click workarounds — on the first launch and every launch after. Very few apps in this space bother with notarization; I do it for every stable release, and for nightly builds too.

The app is built natively for Apple Silicon (M1 and newer), where it runs local AI models beautifully. It also runs on Intel Macs, but those can't run models locally — on an Intel Mac the app skips the AI-engine download entirely and shows a banner in **Settings → Backend** saying local inference isn't supported and only Remote API mode is available. It doesn't switch you over for you: choosing Remote API there is a one-time step you do yourself.

## Linux — Package Managers (Recommended)

Installing through a package repository means updates arrive with your normal system updates (`apt upgrade`, `dnf upgrade`, `yay -Syu`). It's the option I'd pick.

**Debian / Ubuntu / Mint / Pop!_OS**

The quick way — the script adds the repository, then you install:
```bash
curl -fsSL https://apt.frontporchai.app/install.sh | bash
sudo apt install front-porch-ai
```

Or set the repository up by hand:
```bash
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://apt.frontporchai.app/front-porch-ai.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/front-porch-ai.gpg
echo "deb [signed-by=/etc/apt/keyrings/front-porch-ai.gpg] https://apt.frontporchai.app stable main" | sudo tee /etc/apt/sources.list.d/front-porch-ai.list
sudo apt update && sudo apt install front-porch-ai
```

Either route ends up the same: the repository is signed with the project's GPG key, so apt verifies every update it pulls.

**Fedora / RHEL / Rocky / AlmaLinux**

```bash
sudo dnf config-manager --add-repo https://rpm.frontporchai.app/front-porch-ai.repo
sudo dnf install front-porch-ai
```

On **openSUSE**, grab the `.rpm` from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases) and install it with your package manager.

**Arch Linux (AUR)**

```bash
yay -S front-porch-ai-bin        # stable
```

There's also `front-porch-ai-beta-bin` on the AUR — the name is leftover; it tracks the most recent nightly. The two **conflict with each other**, so pick one; installing the nightly package replaces the stable one.

**Heads up: the AUR is behind right now.** The AUR packages are pushed automatically when a release goes out, but that push runs against the AUR's own servers, and it is currently being rejected there. `front-porch-ai-bin` is still on **1.1.2** while apt and dnf serve **1.2.0**, and I can't promise a date for the fix. That gap is worth caring about: 1.1.2 can't open `.fpworld` place files at all, so shared Places won't import until the package catches up. Until it does, install the `.AppImage` or `.tar.gz` from the [Releases page](https://github.com/linux4life1/front-porch-AI/releases) — those are always current — and check the installed version rather than assuming `yay -Syu` got you there.

## Linux — AppImage and Manual Packages

Prefer no repository? The [Releases page](https://github.com/linux4life1/front-porch-AI/releases) has:

- **`Front_Porch_AI-Linux.AppImage`** — download it, make it executable, and run it:
  ```bash
  chmod +x Front_Porch_AI-Linux.AppImage
  ./Front_Porch_AI-Linux.AppImage
  ```
  The app and every AI engine library it uses live inside that one file. AppImages need FUSE 2 to mount themselves, and recent Ubuntu and Fedora releases no longer install it by default — so this is the one thing you may have to add by hand. The package name differs by distro: `libfuse2` on Debian / Ubuntu / Mint / Pop!_OS (`libfuse2t64` on Ubuntu 24.04 and newer), `fuse-libs` on Fedora, `fuse2` on Arch.
- **`Front_Porch_AI-Linux.deb`** and **`Front_Porch_AI-Linux.rpm`** — one-off installs of exactly the same packages the repositories serve.
- **`Front_Porch_AI_Linux.tar.gz`** — a plain folder you can extract anywhere and run directly, if you'd rather not install anything at all.

Whichever you choose, you need a normal GTK 3 desktop environment underneath — every mainstream desktop distro already has one.

---

## Nightly Builds

Everything in the current stable release really is in stable. **Nightly** is the only early-access channel — a fresh build of Rawhide most mornings whenever there's new work to ship; quiet days are skipped. They're tagged `nightly-…` and flagged "Pre-release" on the [Releases page](https://github.com/linux4life1/front-porch-AI/releases). There is no beta series.

**What you can download.** Nightlies come as a Windows installer, a macOS `.pkg`, a Linux AppImage, and a Linux `.tar.gz`. There is no nightly `.deb` or `.rpm`, and nightlies never go into the apt/dnf repositories — those carry stable only. On Arch, `front-porch-ai-beta-bin` in the AUR follows the nightlies (the package name is leftover).

**Your stable install stays safe.** Nightlies keep everything — characters, chats, settings, models — in a separate `FrontPorchAI-Beta` folder (the name is leftover from when there was a beta channel) with their own settings, so they never touch your stable data. You can run stable and a nightly side by side. The first time a nightly starts it offers to copy your stable database across, so you can try new features with your existing characters; your stable copy is left untouched either way, and you can decline.

**Backups & Restore is limited on nightlies.** The **Backups & Restore** page opens but its contents are replaced by a notice, so there is no way to browse or roll back a snapshot there. The automatic snapshots themselves keep running: a nightly still saves a copy of its database every half hour, into its own `FrontPorchAI-Beta` folder, on the same schedule stable uses. If you need to restore one while you're on a nightly, the files are sitting in a `backups` folder next to that build's database.

A backup is a copy of the **database file** only — your chats, your characters' records, and the rest of the database rows. Settings aren't in it (they're stored separately from the database), and neither are image files, so a backup won't bring back a character card image you deleted.

**macOS.** Nightly `.pkg` files are signed and notarized just like stable ones.

Expect occasional rough edges — that's the deal with early builds. Bug reports on [Discord](https://discord.gg/e4tET6rpdv) are always welcome.

---

## After Installing

There's no manual setup, and nothing gets downloaded without you asking for it.

1. **First launch asks one question:** should the app run the built-in AI engine (KoboldCpp) for you, or do you have your own backend already — OpenRouter, Nano-GPT, oMLX, LM Studio, or any OpenAI-compatible API? Choose the built-in engine (or "Not sure yet") and it starts fetching quietly in the background while you carry on setting things up. Choose your own backend and nothing is downloaded at all. You can change your mind any time in **Settings → Backend**.
2. **It looks at your hardware** — graphics card, video memory, system memory — and picks sensible defaults.
3. **It drops you on the home screen**, ready to add characters and models.

From there, open **Manage Models** in the sidebar to download your first AI model — see [Getting Started](getting-started.md#powering-the-ai-local-or-remote) for advice on picking one.

**Voice features.** Text-to-speech and voice input run inside the app itself. There's no Python to install, no helper program, and nothing extra to set up — the first time you switch one on, the app fetches the small voice or speech model it needs.

**Where your files live.** Characters, chats, models, and images all sit in a **FrontPorchAI** folder inside your Documents folder (**FrontPorchAI-Beta** for nightlies — leftover name). You can move it in **Settings → Advanced → Data Directory**.

**How updates reach you** depends on how you installed:

| How you installed | How updates arrive |
| --- | --- |
| Windows installer | The app notices new versions and can install them for you |
| macOS `.pkg` | The app notices new versions and can install them for you |
| Linux AppImage | The app notices new versions and can install them for you |
| apt / dnf repository | With your normal system updates (`apt upgrade`, `dnf upgrade`) |
| Arch AUR | `yay -Syu` |
| `.deb`, `.rpm`, or `.tar.gz` you downloaded by hand | Download the newer file yourself |

The in-app updater only appears for the first three. Everywhere else the app deliberately stays quiet and leaves updating to your package manager, so it can't fight with it.

**Chatting from your phone.** There's nothing to install on the phone — the desktop app can serve a full web interface to any browser on your network. See [Web & Phone Access](user-guide.md#web--phone-access) in the User Guide.

---

## Common Install Problems

- **The AppImage does nothing when you run it:** it almost always needs FUSE 2, which most current distros don't install by default. Install `libfuse2` on Debian / Ubuntu / Mint / Pop!_OS (`libfuse2t64` on Ubuntu 24.04 and newer), `fuse-libs` on Fedora, or `fuse2` on Arch — or sidestep it entirely with the `.deb`/`.rpm`/`.tar.gz`.
- **AMD graphics on Linux:** if the app can't see your GPU, make sure your user account is in the `render` and `video` groups, then log out and back in.
- **UI flicker on Linux (Wayland):** try launching with `GDK_BACKEND=x11`.
- **No "check for updates" button:** that's expected on a `.deb`, `.rpm`, `.tar.gz`, or AUR install — your package manager handles updates instead.
- **Anything else:** the [Troubleshooting guide](troubleshooting.md) covers a lot more, and [Discord](https://discord.gg/e4tET6rpdv) is there for the rest.

---

## For Developers: Building from Source

Everything below is for people who want to hack on the app. Regular users can stop reading here. 🙂

**Prerequisites**

- [Flutter SDK](https://docs.flutter.dev/get-started/install) **3.47.0** — the exact version CI builds and tests with. The project needs Dart 3.10.8 or newer. macOS **13.3 Ventura** is the floor.
- Git

That's the whole list — voice, speech-to-text, character expressions and memory embeddings all run **in-process** via libraries that ship with the app's packages. No Rust and no Python toolchain to set up. (The language model itself is the exception, and always has been: KoboldCpp is a separate local server that the app downloads, then starts and stops for you from the UI.)

**Linux build dependencies**

Ubuntu/Debian:
```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libsecret-1-dev libunwind-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

Fedora:
```bash
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libsecret-devel gstreamer1-devel gstreamer1-plugins-base-devel libstdc++-devel
```

Arch:
```bash
sudo pacman -S clang cmake ninja pkgconf gtk3 xz libsecret gstreamer gst-plugins-base
```

**Clone and run**

```bash
git clone https://github.com/linux4life1/front-porch-AI.git
cd front-porch-AI
flutter pub get
flutter run
```

The generated database code and the built web/phone interface are both committed, so a fresh clone runs with no extra build steps. You only need Node and npm if you're actually changing the web UI in `web_ui/` — then run `npm ci && npm run build` in that folder, which writes the bundle the Flutter app serves.

**Release builds**

```bash
flutter build windows   # or: flutter build linux
```

On macOS, a plain `flutter build macos` is what you want for local testing.

`./scripts/build-macos.sh` exists too, but read the label before you run it: it is the local equivalent of the **nightly** pipeline, not the stable release one. It builds, code-signs, packages and notarizes — and along the way it renames the bundle to `FrontPorchAI-Rawhide.app`, sets its display name to "Front Porch AI Nightly", and produces `Front_Porch_AI_Rawhide.pkg`. What it does **not** do is change the app's version, so the build still reports itself as a stable release and opens your normal `FrontPorchAI` data folder and database — not the `FrontPorchAI-Beta` one. If you want it sandboxed the way a real nightly is, edit the `appVersion` constant in `lib/app_version.dart` to a pre-release string yourself; that patch is exactly what the nightly workflow applies before it builds. The `.pkg` step also checks for my personal Developer ID Installer certificate by name and stops with an error if it isn't in the keychain, so if you're not me, run it with `--skip-pkg` (and `--skip-sign` as well if you have no signing identity at all).

That's it — the built bundle is self-contained.

---

*Questions? Join the [Discord](https://discord.gg/e4tET6rpdv) — I'm happy to help.*
