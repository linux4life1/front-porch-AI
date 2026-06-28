# Linux/amd64 image that mirrors the GitHub `ubuntu-latest` + Flutter 3.41.1 CI
# runner used by the "Widget Golden Tests" job (.github/workflows/ci.yml). Its
# purpose is to regenerate / check Flutter widget pixel goldens locally with the
# same byte output as CI, so you don't need a CI round-trip for every UI tweak.
#
# Pixel goldens are render-sensitive (anti-aliasing, FreeType version, CPU arch).
# This image fixes the OS (Ubuntu 24.04 == ubuntu-latest) and the Flutter version
# to match CI. On Apple Silicon, build and run it with `--platform linux/amd64`
# so the amd64 toolchain runs under Rosetta and matches the amd64 CI runners.
# It is best-effort local parity — CI's golden job remains authoritative.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip xz-utils zip ca-certificates rsync \
      libglu1-mesa \
 && rm -rf /var/lib/apt/lists/*

# Pin the exact Flutter version the CI job uses (subosito/flutter-action@v2
# downloads this same stable tarball).
ARG FLUTTER_VERSION=3.41.1
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Trust any mounted/copied repo path and warm the toolchain so the first golden
# run inside a container is faster.
RUN git config --global --add safe.directory '*' \
 && flutter --version \
 && flutter precache --universal

WORKDIR /build
