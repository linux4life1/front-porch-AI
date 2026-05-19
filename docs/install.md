# Installation Guide

Front Porch AI is designed to run on a wide variety of hardware and operating systems. This guide covers installation via official package managers, standalone binaries, and building from source.

---

## 📋 Table of Contents
- [🏗️ Hardware Requirements](#️-hardware-requirements)
- [🚀 Installation for Users](#-installation-for-users)
  - [Windows](#windows)
  - [macOS](#macos)
  - [Linux (Package Managers)](#linux-package-managers)
  - [Linux (Standalone / AppImage)](#linux-standalone--appimage)
- [🛠️ Installation for Developers](#️-installation-for-developers)
  - [1. Environment Setup](#1-environment-setup)
  - [2. Cloning & Dependencies](#2-cloning--dependencies)
  - [3. Building the Components](#3-building-the-components)
- [⚙️ Post-Installation Setup](#️-post-installation-setup)
- [❓ Troubleshooting](#-troubleshooting)

---

## 🏗️ Hardware Requirements

Front Porch AI supports a broad range of hardware acceleration backends.

### GPU Acceleration
-   **NVIDIA**: Supported via **CUDA** (RTX 20/30/40/50-series). Flash Attention is enabled for massive performance gains.
-   **AMD**: Supported via **ROCm** or **Vulkan**. Vulkan is recommended for the most consistent experience across various AMD architectures.
-   **Apple Silicon**: Fully supported via **Metal** (M1/M2/M3/M4 chips).
-   **Intel**: Supported via **Vulkan** and native **Intel ARC** drivers.
-   **CPU Only**: Supported as a fallback (AVX2/AVX512 optimized).

### System Memory
-   **Minimum**: 8GB RAM.
-   **Recommended**: 16GB+ RAM (especially for running 7B-13B models locally).

---

## 🚀 Installation for Users

### Windows
1.  Download the latest `.exe` installer from the [Releases](https://github.com/linux4life1/front-porch-AI/releases) page.
2.  Run the installer and follow the on-screen instructions.
3.  **Beta Note**: Beta builds are also available as standalone `.zip` files that do not require installation.

### macOS
1.  Download the `.dmg` from the [Releases](https://github.com/linux4life1/front-porch-AI/releases) page.
2.  Drag **Front Porch AI** to your **Applications** folder.
3.  **Apple Silicon**: Built natively for M-series chips for maximum performance.

### Linux (Package Managers)
We provide official repositories for major distributions to ensure easy updates.

#### **Debian / Ubuntu / Mint / Pop!_OS (APT)**
```bash
curl -fsSL https://apt.dreamersai.art/install.sh | bash
sudo apt install front-porch-ai
```

#### **Fedora / RHEL / openSUSE / CentOS (RPM)**
```bash
sudo dnf config-manager --add-repo https://rpm.dreamersai.art/front-porch-ai.repo
sudo dnf install front-porch-ai
```

#### **Arch Linux (AUR)**
The package is available on the AUR as `front-porch-ai-bin` (stable) or `front-porch-ai-beta-bin` (beta).
```bash
yay -S front-porch-ai-bin
```

### Linux (Standalone / AppImage)
If you prefer not to use a package manager, or are on a different distribution:
1.  Download the `.AppImage` from the [Releases](https://github.com/linux4life1/front-porch-AI/releases) page.
2.  Make it executable: `chmod +x Front_Porch_AI.AppImage`.
3.  Run it. The AppImage bundles all necessary dependencies, including `wpewebkit`.

---

## 🛠️ Installation for Developers

### 1. Environment Setup

-   **Flutter SDK**: 3.10.8 or later.
-   **Rust Toolchain**: Required for the embedding server.
-   **Python 3.8+**: Required for TTS/STT sidecars.

#### **Linux Dependencies**
**Ubuntu/Debian:**
```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libwpewebkit-1.0-dev
```

**Fedora/DNF:**
```bash
sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel xz-devel libstdc++-devel wpewebkit-devel
```

### 2. Cloning & Dependencies
```bash
git clone https://github.com/linux4life1/front-porch-AI.git
cd front-porch-AI
flutter pub get
```

### 3. Building the Components
1.  **Embedding Server (Rust)**:
    ```bash
    cargo build --release --manifest-path tools/embed_server/Cargo.toml
    ```
2.  **App**:
    -   **Windows**: `flutter build windows`
    -   **macOS**: `./scripts/build-macos.sh`
    -   **Linux**: `flutter build linux`

---

## ⚙️ Post-Installation Setup

### LLM Backend (KoboldCpp)
Front Porch AI manages KoboldCpp for you.
1.  In the app, go to **Settings > AI Settings**.
2.  Use the **Hardware Detection** tool to auto-select the best backend (CUDA, ROCm, Metal, or Vulkan).
3.  Download a model via the **Model Hub** or point to an existing GGUF file.

### Python Sidecars (TTS/STT)
Install the dependencies for local voice features:
```bash
pip install kokoro-onnx soundfile faster-whisper
```

---

## ❓ Troubleshooting

-   **AMD/ROCm on Linux**: Ensure your user is in the `render` and `video` groups to access GPU acceleration.
-   **Missing Browser import**: If importing from Chub.ai fails on Linux, ensure `wpewebkit` is installed (or use the AppImage).
-   **Wayland**: If experiencing UI flickers on Linux, try running with `GDK_BACKEND=x11`.

---

*Join our [Discord Community](https://discord.gg/e4tET6rpdv) for live support!*
