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

import 'dart:io';
import 'package:front_porch_ai/models/hf_model.dart';

/// Metadata for a locally stored GGUF model file.
/// Provides parsed information about the model without requiring full GGUF parsing.
class LocalModelInfo {
  /// Full filesystem path to the model file.
  final String path;

  /// Just the filename (e.g., "model-Q4_K_M.gguf").
  final String filename;

  /// File size in bytes.
  final int sizeBytes;

  /// Modification time of the file.
  final DateTime modified;

  /// Parsed quantization type from filename.
  final QuantType quantType;

  /// Estimated parameter count in billions (e.g., 8.0 for 8B model).
  final double? paramCountB;

  /// Detected architecture (e.g., "llama", "mistral").
  final String? architecture;

  /// KV cache bytes per token (from GGUF header parsing, if available).
  final int? kvBytesPerToken;

  /// File size in megabytes.
  double get sizeMb => sizeBytes / (1024 * 1024);

  /// File size in gigabytes.
  double get sizeGb => sizeMb / 1024;

  /// Human-readable file size.
  String get sizeDisplay {
    if (sizeGb >= 1.0) {
      return '${sizeGb.toStringAsFixed(2)} GB';
    }
    return '${sizeMb.toStringAsFixed(1)} MB';
  }

  /// Human-readable parameter count (e.g., "8B", "70B").
  String get paramDisplay {
    if (paramCountB == null) return 'Unknown';
    if (paramCountB! >= 1.0) {
      return '${paramCountB!.toStringAsFixed(0)}B';
    }
    return '${(paramCountB! * 1000).toStringAsFixed(0)}M';
  }

  /// Estimated VRAM needed to load this model (just the weights, no KV cache).
  /// This is approximately equal to the file size for GGUF models.
  int get estimatedVramMb => sizeBytes ~/ (1024 * 1024);

  /// Estimated VRAM needed including KV cache for a given context size.
  int estimatedVramWithKv(int contextSize) {
    final baseVram = estimatedVramMb * 1024 * 1024; // Convert to bytes
    final kvVram = (kvBytesPerToken ?? _estimateKvBytes()) * contextSize;
    return (baseVram + kvVram) ~/ (1024 * 1024); // Convert back to MB
  }

  /// Creates a LocalModelInfo from a FileSystemEntity.
  /// Parses metadata from the filename without reading the file.
  factory LocalModelInfo.fromEntity(FileSystemEntity entity) {
    final stat = entity.statSync();
    final filename = entity.path.split(Platform.pathSeparator).last;

    return LocalModelInfo(
      path: entity.path,
      filename: filename,
      sizeBytes: stat.size,
      modified: stat.modified,
      kvBytesPerToken: null, // Will be populated by GGUFParser if needed
    );
  }

  /// Creates a LocalModelInfo with all fields specified.
  LocalModelInfo({
    required this.path,
    required this.filename,
    required this.sizeBytes,
    required this.modified,
    this.paramCountB,
    this.architecture,
    this.kvBytesPerToken,
  }) : quantType = QuantType.fromFilename(filename);

  /// Creates an updated copy with new KV bytes per token.
  LocalModelInfo withKvBytes(int? bytesPerToken) {
    return LocalModelInfo(
      path: path,
      filename: filename,
      sizeBytes: sizeBytes,
      modified: modified,
      paramCountB: paramCountB,
      architecture: architecture,
      kvBytesPerToken: bytesPerToken,
    );
  }

  /// Estimates KV cache bytes per token based on architecture heuristics.
  /// Used when GGUF header hasn't been parsed yet.
  int _estimateKvBytes() {
    // Rough estimates based on common architectures
    // These are FP16 values; actual KV cache may be quantized
    if (paramCountB != null) {
      // Very rough estimate: larger models tend to have larger hidden dims
      if (paramCountB! >= 70) return 4096;   // 70B class
      if (paramCountB! >= 13) return 2048;   // 13B class
      if (paramCountB! >= 7) return 1024;    // 7-8B class
      if (paramCountB! >= 3) return 512;     // 3B class
    }
    return 1024; // Default estimate for 7B-class model
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalModelInfo && other.path == path;
  }

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'LocalModelInfo($filename, $sizeDisplay, $quantType)';
}
