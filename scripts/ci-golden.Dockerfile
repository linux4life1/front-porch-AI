# The `fpai-golden` image scripts/ci-local.sh runs the Linux CI-parity jobs
# in. Reconstructed from `docker history fpai-golden:3.41.1` (the original
# Dockerfile was never committed); keep FLUTTER_VERSION in lock-step with the
# `flutter-version:` used by .github/workflows/ci.yml or the local gate
# false-fails on pub get / renders goldens with the wrong engine.
#
# Rebuild (from the repo root):
#   docker build --platform linux/amd64 \
#     --build-arg FLUTTER_VERSION=3.47.0 \
#     -t fpai-golden:3.47.0 -f scripts/ci-golden.Dockerfile scripts
#
# Desktop/E2E deps (GTK, xvfb, ninja, gstreamer) are baked in so
# `scripts/ci-local.sh e2e` does not re-apt on every run. Containers are
# still --rm for isolation; the *image* holds the packages.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip xz-utils zip ca-certificates rsync \
      libglu1-mesa \
      clang cmake ninja-build pkg-config \
      libgtk-3-dev xvfb \
      libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev \
      liblzma-dev libstdc++-12-dev \
      libegl1 libgl1-mesa-dri libglx-mesa0 \
      libxkbcommon0 libxkbcommon-x11-0 \
      fonts-noto-core \
  && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.47.0
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
  && tar -xJf /tmp/flutter.tar.xz -C /opt \
  && rm /tmp/flutter.tar.xz
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Software GL helps headless xvfb; matches CI's virtual display path.
ENV LIBGL_ALWAYS_SOFTWARE=1
RUN git config --global --add safe.directory '*' \
  && flutter --version \
  && flutter config --enable-linux-desktop \
  && flutter precache --universal --linux
WORKDIR /build
