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

// Which KoboldCpp build this machine runs, where it is downloaded from, and
// how its version reads and compares on the Backend tab.

import 'dart:io';

import 'package:front_porch_ai/utils/utils.dart';

/// The engine file name for this machine. No AVX2 wins over every GPU
/// choice: each AVX2 build (cuda/rocm/nocuda alike) crashes there, and the
/// oldpc build is "Cuda11 + AVX1" (CUDA offload kept for older NVIDIA; no
/// ROCm, so AMD falls back to CPU).
String koboldExecutableName({
  required bool onLinux,
  required bool hasAvx2,
  required bool useRocm,
  required bool hasCuda,
  required bool intelCpu,
}) {
  if (Platform.isWindows) {
    return hasAvx2 ? 'koboldcpp.exe' : 'koboldcpp-oldpc.exe';
  }
  if (onLinux) {
    if (!hasAvx2) return 'koboldcpp-linux-x64-oldpc';
    if (useRocm) return 'koboldcpp-linux-x64-rocm';
    if (hasCuda) return 'koboldcpp-linux-x64';
    return 'koboldcpp-linux-x64-nocuda';
  }
  if (Platform.isMacOS) {
    return intelCpu ? 'koboldcpp-mac-x64' : 'koboldcpp-mac-arm64';
  }
  return 'koboldcpp';
}

/// Where this machine's engine build is downloaded from.
String koboldDownloadUrl({
  required bool onLinux,
  required bool hasAvx2,
  required bool useRocm,
  required bool hasCuda,
  required bool intelCpu,
}) {
  const base =
      'https://github.com/LostRuins/koboldcpp/releases/latest/download';
  if (Platform.isWindows) {
    return hasAvx2 ? '$base/koboldcpp.exe' : '$base/koboldcpp-oldpc.exe';
  }
  if (onLinux) {
    if (!hasAvx2) return '$base/koboldcpp-linux-x64-oldpc';
    if (useRocm) return 'https://koboldai.org/cpplinuxrocm';
    if (hasCuda) return '$base/koboldcpp-linux-x64';
    return '$base/koboldcpp-linux-x64-nocuda';
  }
  if (Platform.isMacOS) {
    return intelCpu
        ? 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-mac-x64'
        : 'https://github.com/LostRuins/koboldcpp/releases/latest/download/koboldcpp-mac-arm64';
  }
  throw Exception('Unsupported platform');
}

/// Whether the release found ([remoteVersion], for the build [remoteFor])
/// is newer than the installed build [exeName].
bool engineUpdateAvailable({
  required String exeName,
  required String? remoteFor,
  required String? remoteVersion,
  required int? remoteAssetSize,
  required String? localVersion,
  required int? localSize,
}) {
  if (remoteFor != null && remoteFor != exeName) return false;
  // The ROCm build's release is rebuilt in place under one name, and the
  // engine reports its own version once it runs, so only a different
  // file on the release says it changed.
  if (remoteVersion != null && remoteVersion.startsWith('rocm-rolling')) {
    return remoteAssetSize != null && localSize != remoteAssetSize;
  }
  if (localVersion == null) return true;
  if (remoteVersion == null) return false;
  if (localVersion != remoteVersion) return true;
  if (remoteAssetSize != null &&
      localSize != null &&
      localSize != remoteAssetSize) {
    return true;
  }
  return false;
}

/// The installed engine as the Backend tab names it. A numbered release
/// reads "v1.122.1"; the ROCm build's rolling name reads as it is.
String engineVersionDisplay(String? localVersion, int? localSize) {
  if (localVersion == null) return '';
  final v = RegExp(r'^\d').hasMatch(localVersion)
      ? 'v$localVersion'
      : localVersion;
  if (localSize == null) return v;
  return '$v, ${formatBytes(localSize)}';
}
