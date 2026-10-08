// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

/// A fresh temp folder by its real path. macOS temp lives under `/var`, a
/// link to `/private/var`, and the ComfyUI-GGUF loader gate refuses any
/// path reached through a link — so a plain `createTempSync` folder fails
/// those checks on a Mac while passing on Linux CI.
Directory realTempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  return Directory(dir.resolveSymbolicLinksSync());
}
