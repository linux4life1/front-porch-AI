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

/// All supported GGUF quantization types.
/// Used for parsing filenames and displaying quant info to users.
enum QuantType {
  // Standard quantizations
  q2K('Q2_K', 0.39),
  q3K('Q3_K', 0.51),
  q4_0('Q4_0', 0.53),
  q4K('Q4_K', 0.56),
  q5_0('Q5_0', 0.66),
  q5K('Q5_K', 0.69),
  q6K('Q6_K', 0.80),
  q8_0('Q8_0', 0.99),

  // IQ (improved quantization) types
  iq2XXS('IQ2_XXS', 0.31),
  iq2XS('IQ2_XS', 0.36),
  iq3XXS('IQ3_XXS', 0.41),
  iq3XS('IQ3_XS', 0.44),
  iq3S('IQ3_S', 0.46),
  iq3M('IQ3_M', 0.48),
  iq4X('IQ4_X', 0.49),
  iq4N('IQ4_NLS', 0.51),
  iq4XL('IQ4_XL', 0.53),
  iq4S('IQ4_S', 0.53),
  iq4M('IQ4_M', 0.56),
  iq5X('IQ5_X', 0.61),
  iq5S('IQ5_S', 0.63),
  iq5M('IQ5_M', 0.66),
  iq6M('IQ6_M', 0.75),

  // Integer quantizations
  i2S('I2_S', 0.28),
  i3S('I3_S', 0.41),
  i4('I4', 0.50),
  i8('I8', 1.00),

  // Float types
  fp16('FP16', 2.0),
  fp32('FP32', 4.0),

  // Unknown/unrecognized
  unknown('Unknown', 0.0);

  final String label;
  final double bytesPerParam;

  const QuantType(this.label, this.bytesPerParam);

  /// Parses a QuantType from a GGUF filename.
  /// Handles common patterns like Q4_K_M, Q5_K_S, IQ2_XXS, etc.
  static QuantType fromFilename(String filename) {
    final upper = filename.toUpperCase();

    // Check for specific variants first (more specific patterns)
    if (upper.contains('Q4_K_M') || upper.contains('Q4KM')) return q4K;
    if (upper.contains('Q4_K_S') || upper.contains('Q4KS')) return q4K;
    if (upper.contains('Q4_K')) return q4K;
    if (upper.contains('Q5_K_M') || upper.contains('Q5KM')) return q5K;
    if (upper.contains('Q5_K_S') || upper.contains('Q5KS')) return q5K;
    if (upper.contains('Q5_K')) return q5K;
    if (upper.contains('Q3_K_M') || upper.contains('Q3KM')) return q3K;
    if (upper.contains('Q3_K_S') || upper.contains('Q3KS')) return q3K;
    if (upper.contains('Q3_K_L') || upper.contains('Q3KL')) return q3K;
    if (upper.contains('Q3_K')) return q3K;
    if (upper.contains('Q2_K')) return q2K;
    if (upper.contains('Q6_K')) return q6K;

    // IQ types
    if (upper.contains('IQ2_XXS')) return iq2XXS;
    if (upper.contains('IQ2_XS')) return iq2XS;
    if (upper.contains('IQ3_XXS')) return iq3XXS;
    if (upper.contains('IQ3_XS')) return iq3XS;
    if (upper.contains('IQ3_S')) return iq3S;
    if (upper.contains('IQ3_M')) return iq3M;
    if (upper.contains('IQ4_XL')) return iq4XL;
    if (upper.contains('IQ4_NLS')) return iq4N;
    if (upper.contains('IQ4_X')) return iq4X;
    if (upper.contains('IQ4_S')) return iq4S;
    if (upper.contains('IQ4_M')) return iq4M;
    if (upper.contains('IQ5_X')) return iq5X;
    if (upper.contains('IQ5_S')) return iq5S;
    if (upper.contains('IQ5_M')) return iq5M;
    if (upper.contains('IQ6_M')) return iq6M;

    // Integer types
    if (upper.contains('I2_S')) return i2S;
    if (upper.contains('I3_S')) return i3S;
    if (upper.contains('I4_') || (upper.contains('I4') && !upper.contains('I4_'))) return i4;
    if (upper.contains('I8')) return i8;

    // Standard types (check these after variants)
    if (upper.contains('Q8_0')) return q8_0;
    if (upper.contains('Q6')) return q6K;
    if (upper.contains('Q5_0')) return q5_0;
    if (upper.contains('Q5')) return q5K;
    if (upper.contains('Q4_0')) return q4_0;
    if (upper.contains('Q4')) return q4K;
    if (upper.contains('Q3')) return q3K;
    if (upper.contains('Q2')) return q2K;

    // Float types
    if (upper.contains('FP16') || upper.contains('F16')) return fp16;
    if (upper.contains('FP32') || upper.contains('F32')) return fp32;

    return unknown;
  }

  /// Returns a display-friendly color category for the quantization.
  /// Higher quality = warmer color, lower quality = cooler color.
  String get colorCategory {
    if (bytesPerParam >= 1.5) return 'red';     // FP16/FP32
    if (bytesPerParam >= 0.9) return 'orange';   // Q8
    if (bytesPerParam >= 0.7) return 'yellow';   // Q6, Q5K
    if (bytesPerParam >= 0.55) return 'green';   // Q5, Q4K
    if (bytesPerParam >= 0.45) return 'blue';    // Q4, Q3K
    return 'purple';                             // Q3, Q2, IQ variants
  }
}

/// VRAM fit status for a model on the user's hardware.
enum VramFitStatus {
  /// Model fits with more than 2GB headroom remaining.
  fits,

  /// Model fits but leaves less than 2GB headroom.
  tight,

  /// Model exceeds available VRAM.
  exceeds;

  /// Get the color for this status indicator.
  String get color {
    switch (this) {
      case fits:
        return 'green';
      case tight:
        return 'yellow';
      case exceeds:
        return 'red';
    }
  }

  /// Get a human-readable description.
  String description(int neededMb, int availableMb) {
    switch (this) {
      case fits:
        final headroom = ((availableMb - neededMb) / 1024).toStringAsFixed(1);
        return '$headroom GB free after loading';
      case tight:
        final headroom = ((availableMb - neededMb) / 1024).toStringAsFixed(1);
        return 'Only $headroom GB free — may be tight';
      case exceeds:
        final overage = ((neededMb - availableMb) / 1024).toStringAsFixed(1);
        return '$overage GB over your VRAM';
    }
  }
}

/// Represents a single GGUF file within a HuggingFace model repository.
class HFModelFile {
  /// The filename as stored on HuggingFace (e.g., "model-Q4_K_M.gguf").
  final String filename;

  /// The full download URL for this file.
  final String downloadUrl;

  /// File size in bytes.
  final int sizeBytes;

  /// The parent repository ID (e.g., "bartowski/Meta-Llama-3-8B-Instruct-GGUF").
  final String repoId;

  /// Parsed quantization type from the filename.
  final QuantType quantType;

  /// Estimated parameter count in billions (e.g., 8.0 for 8B model).
  /// Parsed from filename or estimated from file size.
  final double? paramCountB;

  /// Architecture name if detectable from filename (e.g., "llama", "mistral").
  final String? architecture;

  /// The HuggingFace API URL for this specific file (for metadata).
  String get hfApiUrl => 'https://huggingface.co/$repoId/raw/main/$filename';

  /// File size in megabytes (rounded to 1 decimal).
  double get sizeMb => (sizeBytes / (1024 * 1024));

  /// File size in gigabytes (rounded to 2 decimals).
  double get sizeGb => sizeMb / 1024;

  /// Human-readable file size string.
  String get sizeDisplay {
    if (sizeGb >= 1.0) {
      return '${sizeGb.toStringAsFixed(2)} GB';
    }
    return '${sizeMb.toStringAsFixed(1)} MB';
  }

  HFModelFile({
    required this.filename,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.repoId,
    this.paramCountB,
    this.architecture,
  }) : quantType = QuantType.fromFilename(filename);

  /// Creates an HFModelFile from a HuggingFace API response map.
  /// Expected format from /api/models/{repoId}/tree/main endpoint.
  factory HFModelFile.fromApiMap(Map<String, dynamic> map, String repoId) {
    final path = map['path'] as String? ?? '';
    final size = (map['size'] as num?)?.toInt() ?? 0;

    // Build direct download URL
    final downloadUrl = 'https://huggingface.co/$repoId/resolve/main/$path';

    // Try to extract param count from filename
    double? params;
    try {
      params = _extractParamCount(path);
    } catch (_) {
      // Estimation from file size if Q4 detected (~0.5 bytes per param)
      final quant = QuantType.fromFilename(path);
      if (quant.bytesPerParam > 0) {
        params = (size / (quant.bytesPerParam * 1e9));
      }
    }

    // Try to detect architecture from filename
    final arch = _detectArchitecture(path);

    return HFModelFile(
      filename: path,
      downloadUrl: downloadUrl,
      sizeBytes: size,
      repoId: repoId,
      paramCountB: params,
      architecture: arch,
    );
  }

  /// Extracts parameter count from common filename patterns.
  /// Handles: 7B, 8B, 13B, 70B, 0.5B, 128B, etc.
  static double? _extractParamCount(String filename) {
    // Pattern: number followed by B (case insensitive)
    // Matches: 7B, 8B, 13B, 70B, 0.5B, 1.5B, 128B
    final pattern = RegExp(r'(\d+\.?\d*)\s*B', caseSensitive: false);
    final match = pattern.firstMatch(filename);
    if (match != null) {
      return double.tryParse(match.group(1)!);
    }
    return null;
  }

  /// Detects model architecture from filename keywords.
  static String? _detectArchitecture(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('llama')) return 'llama';
    if (lower.contains('mistral')) return 'mistral';
    if (lower.contains('mixtral')) return 'mixtral';
    if (lower.contains('gemma')) return 'gemma';
    if (lower.contains('phi')) return 'phi';
    if (lower.contains('qwen')) return 'qwen';
    if (lower.contains('yi-') || lower.contains('_yi_')) return 'yi';
    if (lower.contains('command-r')) return 'command-r';
    if (lower.contains('mpt')) return 'mpt';
    if (lower.contains('falcon')) return 'falcon';
    return null;
  }

  @override
  String toString() => 'HFModelFile($filename, $sizeDisplay, $quantType)';
}

/// Represents a HuggingFace model repository containing GGUF files.
class HFModel {
  /// Full repository ID (e.g., "bartowski/Meta-Llama-3-8B-Instruct-GGUF").
  final String id;

  /// Repository author/organization name.
  final String author;

  /// Model name without author prefix.
  String get name => id.split('/').last;

  /// Number of likes/stars on HuggingFace.
  final int likes;

  /// Number of downloads on HuggingFace.
  final int downloads;

  /// Model tags from HuggingFace.
  final List<String> tags;

  /// Model description snippet.
  final String? description;

  /// Whether this model has a pipeline tag (indicates it's ready to use).
  final bool hasPipelineTag;

  /// URL to the model card on HuggingFace.
  String get hfUrl => 'https://huggingface.co/$id';

  /// List of available GGUF files for this model.
  /// Populated after calling [fetchFiles].
  final List<HFModelFile> files;

  HFModel({
    required this.id,
    required this.author,
    this.likes = 0,
    this.downloads = 0,
    this.tags = const [],
    this.description,
    this.hasPipelineTag = false,
    this.files = const [],
  });

  /// Creates an HFModel from a HuggingFace API search response.
  factory HFModel.fromSearchResult(Map<String, dynamic> map) {
    final modelId = map['id'] as String? ?? '';
    final author = map['author'] as String? ?? modelId.split('/').first;
    final tags = (map['tags'] as List<dynamic>?)?.cast<String>() ?? [];

    return HFModel(
      id: modelId,
      author: author,
      likes: (map['likes'] as num?)?.toInt() ?? 0,
      downloads: (map['downloads'] as num?)?.toInt() ?? 0,
      tags: tags,
      description: map['description'] as String?,
      hasPipelineTag: tags.contains('text-generation'),
    );
  }

  /// Returns a formatted display string for download count.
  String get downloadsDisplay {
    if (downloads >= 1000000) {
      return '${(downloads / 1000000).toStringAsFixed(1)}M';
    } else if (downloads >= 1000) {
      return '${(downloads / 1000).toStringAsFixed(1)}K';
    }
    return downloads.toString();
  }

  /// Returns a formatted display string for likes.
  String get likesDisplay {
    if (likes >= 1000) {
      return '${(likes / 1000).toStringAsFixed(1)}K';
    }
    return likes.toString();
  }

  /// Adds files to this model's file list.
  HFModel withFiles(List<HFModelFile> newFiles) {
    return HFModel(
      id: id,
      author: author,
      likes: likes,
      downloads: downloads,
      tags: tags,
      description: description,
      hasPipelineTag: hasPipelineTag,
      files: List.unmodifiable(newFiles),
    );
  }

  @override
  String toString() => 'HFModel($id, ${files.length} files, $likes likes)';
}
