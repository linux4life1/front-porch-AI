// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:ffi';
import 'dart:io';

/// Known-good OpenCode CLI. Upgrades are a tap, never auto-latest on launch.
const kOpenCodePinnedVersion = '1.18.30';

/// Published zip is ~44MB. Honesty copy; GitHub asset size wins when known.
const kOpenCodePinMegabytes = 44;

const kOpenCodeGitHubOwner = 'anomalyco';
const kOpenCodeGitHubRepo = 'opencode';
const kOpenCodeVersionFileName = '.opencode_version';

const kOpenCodeGitHubLatestUrl =
    'https://api.github.com/repos/$kOpenCodeGitHubOwner/$kOpenCodeGitHubRepo/'
    'releases/latest';

String openCodeCurrentOs() {
  if (Platform.isMacOS) return 'darwin';
  if (Platform.isWindows) return 'windows';
  return 'linux';
}

String openCodeCurrentArch() {
  switch (Abi.current()) {
    case Abi.macosArm64:
    case Abi.linuxArm64:
    case Abi.windowsArm64:
      return 'arm64';
    default:
      return 'x64';
  }
}

String openCodeReleaseAssetName({required String os, required String arch}) {
  return 'opencode-$os-$arch.zip';
}

String openCodeDownloadUrl({
  required String version,
  required String os,
  required String arch,
}) {
  final asset = openCodeReleaseAssetName(os: os, arch: arch);
  return 'https://github.com/$kOpenCodeGitHubOwner/$kOpenCodeGitHubRepo/'
      'releases/download/v$version/$asset';
}

Uri openCodePinnedDownloadUri({String? os, String? arch}) {
  return Uri.parse(
    openCodeDownloadUrl(
      version: kOpenCodePinnedVersion,
      os: os ?? openCodeCurrentOs(),
      arch: arch ?? openCodeCurrentArch(),
    ),
  );
}

bool openCodeLooksLikeBrewPath(String path) {
  final n = path.replaceAll('\\', '/').toLowerCase();
  if (n.contains('/opt/homebrew/')) return true;
  if (n.contains('/home/linuxbrew/')) return true;
  if (n.contains('/.linuxbrew/')) return true;
  if (n.endsWith('/usr/local/bin/opencode')) return true;
  if (n.endsWith('/usr/local/bin/opencode.exe')) return true;
  return false;
}

bool openCodeLooksLikeUserConfigPath(String path) {
  final n = path.replaceAll('\\', '/');
  if (n.contains('/.config/opencode')) return true;
  if (n.toLowerCase().contains('/appdata/roaming/opencode')) return true;
  return false;
}

/// Settings / Waifu honesty: on-disk vs pin vs GitHub latest. Tap still
/// installs the pin, never auto-latest.
String openCodeUpgradeHonesty({
  required String? installed,
  required String pinned,
  String? remote,
  int megabytes = kOpenCodePinMegabytes,
}) {
  final remoteBit = (remote == null || remote.isEmpty)
      ? ''
      : ' GitHub latest is $remote.';
  if (installed == null || installed.isEmpty) {
    return 'OpenCode $pinned is not in the closet yet (~${megabytes}MB).'
        '$remoteBit Homebrew is not used.';
  }
  if (installed != pinned) {
    return 'OpenCode $installed → $pinned, ~${megabytes}MB.$remoteBit';
  }
  return 'OpenCode $pinned is current (pin).$remoteBit '
      'Homebrew and ~/.config/opencode are not the product copy.';
}

String openCodeUpgradeButtonLabel({
  required String? installed,
  required String pinned,
}) {
  if (installed == null || installed.isEmpty) {
    return 'Download $pinned (~${kOpenCodePinMegabytes}MB)';
  }
  if (installed != pinned) {
    return 'Update to $pinned (~${kOpenCodePinMegabytes}MB)';
  }
  return 'Up to date';
}
