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

/// Available image generation subjects.
///
/// The Image Studio and the `/image` slash command share these:
/// - **customPrompt**: a freeform prompt. When the prompt text is empty but
///   recent chat narrative is supplied, the builder distills the *current
///   scene* from it (this is what the bare `/image` / `/image scene` command
///   uses — the former standalone "Visualize Scene" mode was folded in here).
/// - **characterPortrait**: a portrait built from a character's appearance.
/// - **userAvatar**: a portrait built from the user persona's appearance.
///
/// (The old `visualizeScene` and `chatBackground` modes were removed — the
/// former is now `customPrompt` with scene context, the latter was retired
/// because generating a figure-free chat background confused users. Backgrounds
/// are still chosen from the Background settings dialog.)
enum ImageGenMode { customPrompt, characterPortrait, userAvatar }

/// Local image-generation backend options.
enum ImageGenBackend {
  remote,
  a1111,
  drawThings,
  comfyUi;

  static ImageGenBackend fromKey(String key) {
    switch (key) {
      case 'a1111':
        return ImageGenBackend.a1111;
      case 'drawthings':
        return ImageGenBackend.drawThings;
      case 'comfyui':
        return ImageGenBackend.comfyUi;
      default:
        return ImageGenBackend.remote;
    }
  }

  String get key {
    switch (this) {
      case ImageGenBackend.a1111:
        return 'a1111';
      case ImageGenBackend.drawThings:
        return 'drawthings';
      case ImageGenBackend.comfyUi:
        return 'comfyui';
      case ImageGenBackend.remote:
        return 'remote';
    }
  }

  String get label {
    switch (this) {
      case ImageGenBackend.a1111:
        return 'AUTOMATIC1111';
      case ImageGenBackend.drawThings:
        return 'Draw Things';
      case ImageGenBackend.comfyUi:
        return 'ComfyUI';
      case ImageGenBackend.remote:
        return 'Remote API';
    }
  }
}

/// Metadata for an image model available via the remote API.
class ImageModelInfo {
  final String id;
  final String name;

  /// Whether this model costs extra per-prompt (true) or is included
  /// with a Nano-GPT Pro subscription (false).
  final bool isPaid;

  /// Pricing information from OpenRouter (if available).
  /// Format: "prompt_cost / completion_cost per token" or raw JSON string.
  final String? pricingInfo;

  /// The `size` values the host lists for this model, verbatim (`1024x1536`,
  /// `1024*1536`, `16:9`, `2k`, `auto`). Empty when the host lists none.
  final List<String> resolutions;

  /// Host price per image keyed by a [resolutions] value, in USD.
  final Map<String, double> pricePerImage;

  /// Whether the host says this model takes a picture to edit.
  final bool canEdit;

  const ImageModelInfo({
    required this.id,
    this.name = '',
    this.isPaid = true,
    this.pricingInfo,
    this.resolutions = const [],
    this.pricePerImage = const {},
    this.canEdit = false,
  });

  ImageModelInfo copyWith({bool? isPaid}) => ImageModelInfo(
    id: id,
    name: name,
    isPaid: isPaid ?? this.isPaid,
    pricingInfo: pricingInfo,
    resolutions: resolutions,
    pricePerImage: pricePerImage,
    canEdit: canEdit,
  );

  String get displayName => name.isNotEmpty ? name : id;

  /// Human-readable description including pricing if available.
  String get description {
    if (pricingInfo != null && pricingInfo!.isNotEmpty) {
      return '$displayName — $pricingInfo';
    }
    return displayName;
  }
}
