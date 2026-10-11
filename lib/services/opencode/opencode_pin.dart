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

import 'package:crypto/crypto.dart';

/// Honesty copy when GitHub has not told us the zip size yet.
const kOpenCodeDownloadMegabytes = 44;

const kOpenCodeGitHubOwner = 'anomalyco';
const kOpenCodeGitHubRepo = 'opencode';
const kOpenCodeVersionFileName = '.opencode_version';

/// The OpenCode release Waifu Coder is built and tested against. The voice
/// plugin, SSE parsing and permission maps depend on its behaviour, so
/// Porch installs this one, not whatever GitHub calls latest.
const kOpenCodePinnedVersion = '1.18.30';

/// SHA-256 of each [kOpenCodePinnedVersion] release asset. A download that
/// does not match is refused before it is unpacked.
const kOpenCodePinnedSha256 = {
  'opencode-darwin-arm64.zip':
      'a5e43d6887386efc7d68ce49ae28e3bbdfdee3dfd1d7169b612c3ce67e53b1e8',
  'opencode-darwin-x64.zip':
      '7453007e58ff122401438d95ccb24334874b5908dcaee77883f96c23395d5710',
  'opencode-linux-x64.tar.gz':
      '55007246858165496ff85ba1c2b648f7421e8e2013bf4189a680c9ff8e699d17',
  'opencode-linux-arm64.tar.gz':
      '4111a55c2a02c0fac314bd51e9a2330280e6d29d2b85b9554fff6d62612566ed',
  'opencode-windows-x64.zip':
      'c8c0e0d05ac3dac544a0edfad8de9eb244bf46c6c7a131c38619d40fcf31bd1f',
  'opencode-windows-arm64.zip':
      '35d6ff7d80aff5ade71ac06fc32dd89357b5b0bac050fc6db41ecf0929cea560',
};

const kOpenCodePinnedBytes = {
  'opencode-darwin-arm64.zip': 46240880,
  'opencode-darwin-x64.zip': 48433468,
  'opencode-linux-x64.tar.gz': 60557284,
  'opencode-linux-arm64.tar.gz': 60366998,
  'opencode-windows-x64.zip': 60686185,
  'opencode-windows-arm64.zip': 58842155,
};

const kOpenCodeGitHubLatestDownloadBase =
    'https://github.com/$kOpenCodeGitHubOwner/$kOpenCodeGitHubRepo/'
    'releases/latest/download';

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

/// GitHub layout: Mac/Windows zip, Linux tar.gz. Not musl/baseline.
String openCodeReleaseAssetName({required String os, required String arch}) {
  if (os == 'linux') return 'opencode-linux-$arch.tar.gz';
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

/// The release asset for [version], or GitHub latest when it is unknown.
Uri openCodeReleaseDownloadUri(String? version, {String? os, String? arch}) {
  if (version == null || version.isEmpty) {
    return openCodeLatestDownloadUri(os: os, arch: arch);
  }
  return Uri.parse(
    openCodeDownloadUrl(
      version: version,
      os: os ?? openCodeCurrentOs(),
      arch: arch ?? openCodeCurrentArch(),
    ),
  );
}

/// The manager's default version lookup: always the pinned release.
Future<({String tag, int? assetBytes})?> openCodePinnedLookup() async {
  final asset = openCodeReleaseAssetName(
    os: openCodeCurrentOs(),
    arch: openCodeCurrentArch(),
  );
  return (tag: kOpenCodePinnedVersion, assetBytes: kOpenCodePinnedBytes[asset]);
}

/// Throws when [bytes] claim to be the pinned release but do not match its
/// checksum. Other versions only reach here through an injected lookup.
void openCodeVerifyDownload({
  required String? version,
  required List<int> bytes,
  String? os,
  String? arch,
}) {
  if (version != kOpenCodePinnedVersion) return;
  final asset = openCodeReleaseAssetName(
    os: os ?? openCodeCurrentOs(),
    arch: arch ?? openCodeCurrentArch(),
  );
  final want = kOpenCodePinnedSha256[asset];
  final got = sha256.convert(bytes).toString();
  if (want == null || got != want) {
    throw StateError(
      'OpenCode $version download for $asset failed its checksum check',
    );
  }
}

/// Same shape as Kobold: `releases/latest/download/<asset>`.
Uri openCodeLatestDownloadUri({String? os, String? arch}) {
  final asset = openCodeReleaseAssetName(
    os: os ?? openCodeCurrentOs(),
    arch: arch ?? openCodeCurrentArch(),
  );
  return Uri.parse('$kOpenCodeGitHubLatestDownloadBase/$asset');
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

/// Settings / Waifu honesty: on-disk vs the version Porch installs.
String openCodeUpgradeHonesty({
  required String? installed,
  String? remote,
  int megabytes = kOpenCodeDownloadMegabytes,
}) {
  final remoteBit = (remote == null || remote.isEmpty)
      ? ''
      : ' Porch uses $remote.';
  if (installed == null || installed.isEmpty) {
    return 'OpenCode is not in the closet yet (~${megabytes}MB).'
        '$remoteBit Homebrew is not used.';
  }
  if (remote != null && remote.isNotEmpty && installed != remote) {
    return 'OpenCode $installed → $remote, ~${megabytes}MB.';
  }
  if (remote != null && remote.isNotEmpty && installed == remote) {
    return 'OpenCode $remote is current.$remoteBit '
        'Homebrew and ~/.config/opencode are not the product copy.';
  }
  return 'OpenCode $installed is installed.$remoteBit Homebrew is not used.';
}

/// Same button words as the managed Kobold row.
String openCodeUpgradeButtonLabel({
  required String? installed,
  String? remote,
  String? versionError,
}) {
  if (installed == null || installed.isEmpty) {
    return 'Download';
  }
  if (versionError != null && versionError.isNotEmpty) {
    return 'Check (failed)';
  }
  if (remote == null || remote.isEmpty) {
    return 'Check for Updates';
  }
  if (installed != remote) {
    return 'Update to v$remote';
  }
  return 'Up to date';
}
