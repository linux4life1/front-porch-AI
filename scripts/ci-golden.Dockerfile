# The `fpai-golden` image scripts/ci-local.sh runs the Linux CI-parity jobs
# in. Reconstructed from `docker history fpai-golden:3.41.1` (the original
# Dockerfile was never committed); keep FLUTTER_VERSION in lock-step with the
# `flutter-version:` used by .github/workflows/ci.yml or the local gate
# false-fails on pub get / renders goldens with the wrong engine.
#
# Rebuild (from the repo root):
#   docker build --platform linux/amd64 \
#     --build-arg FLUTTER_VERSION=3.44.8 \
#     -t fpai-golden:3.44.8 -f scripts/ci-golden.Dockerfile scripts
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      git curl unzip xz-utils zip ca-certificates rsync \
      libglu1-mesa \
  && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.44.8
RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
  && tar -xJf /tmp/flutter.tar.xz -C /opt \
  && rm /tmp/flutter.tar.xz
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN git config --global --add safe.directory '*' \
  && flutter --version \
  && flutter precache --universal
WORKDIR /build
