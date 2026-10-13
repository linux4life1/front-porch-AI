// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'image_gen_types.dart';
import 'image_studio_remote.dart';
import 'xai_image.dart';

/// What Image Studio's Remote panel says about the chosen host and model.
/// Desktop and the web relay both read these, so the words match.
class RemoteStudioCopy {
  const RemoteStudioCopy._();

  /// The line under a host tile.
  static String hostSub({required bool signedIn, required bool hasKey}) {
    if (signedIn) return 'SuperGrok sign-in';
    return hasKey ? 'Key saved' : 'Add a key';
  }

  static String billing(ImageStudioRemoteHost host, {required bool signedIn}) {
    if (host.id == 'xai' && signedIn) return 'Signed in with SuperGrok.';
    return 'Bills your ${host.label} account per image.';
  }

  static String status(ImageStudioRemoteHost host, int modelCount) {
    switch (host.id) {
      case 'openrouter':
        return 'Reachable · image models listed';
      case 'xai':
        return 'Reachable · Grok Imagine';
      default:
        return 'Reachable · $modelCount models';
    }
  }

  static String keyPrompt(ImageStudioRemoteHost host) =>
      'Paste your ${host.label} key to use it here';

  static String keyHint(ImageStudioRemoteHost host) => switch (host.id) {
    'openrouter' => 'sk-or-…',
    'xai' => 'xai-…',
    _ => 'sk-…',
  };

  static const keyNote =
      'Saved in the same key vault as chat. It does not change chat\'s provider.';

  static String needsKey(ImageStudioRemoteHost host) =>
      'Add ${_article(host.label)} ${host.label} key, or pick another host.';

  static List<String> badges(ImageStudioRemoteHost host, ImageModelInfo m) => [
    'Text to image',
    if (m.canEdit) 'Edit',
    if (host.id == 'nano' && !m.isPaid) 'Pro included',
  ];

  static String price(
    ImageStudioRemoteHost host,
    ImageModelInfo m, {
    String size = '',
  }) {
    switch (host.id) {
      case 'openrouter':
        return 'Price per image comes from OpenRouter’s catalog.';
      case 'xai':
        return 'Uses your SuperGrok sign-in, or bills your xAI key per image.';
    }
    if (!m.isPaid) return 'Included with your Nano-GPT Pro plan.';
    final cost = m.pricePerImage[size] ?? m.pricePerImage.values.firstOrNull;
    if (cost == null) return 'Price per image comes from Nano-GPT’s catalog.';
    return '\$${_money(cost)} per image.';
  }

  static String sizeTitle(ImageStudioRemoteHost host) =>
      host.id == 'xai' ? 'Aspect ratio' : 'Size';

  static String sizeNote(
    ImageStudioRemoteHost host,
    ImageModelInfo? m, {
    String aspect = '',
    String resolution = '',
  }) {
    if (host.id == 'xai') {
      return 'Sends ${remoteSizeLabel(aspect)} at $resolution. xAI takes a '
          'shape and a resolution, not exact pixels.';
    }
    final name = m?.displayName ?? 'This model';
    return 'Sizes $name accepts on Nano-GPT. Other models list their own.';
  }

  static const openRouterSize =
      'OpenRouter does not take a size. The model picks one, so describe the '
      'shape you want in the prompt (for example "tall portrait").';

  static String _article(String word) =>
      RegExp('^[AEIOUaeiou]').hasMatch(word) ||
          word.toLowerCase().startsWith('x')
      ? 'an'
      : 'a';

  static String _money(double value) {
    var text = value.toStringAsFixed(4);
    while (text.endsWith('0') && !text.endsWith('.00')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }
}

/// `1024x1536` and `1024*1536` read as `1024×1536`; `auto` as `Auto`.
String remoteSizeLabel(String value) {
  final pixels = RegExp(r'^(\d+)\s*[x*×]\s*(\d+)$').firstMatch(value.trim());
  if (pixels != null) return '${pixels[1]}×${pixels[2]}';
  if (value.trim().toLowerCase() == 'auto') return 'Auto';
  return value.trim();
}

/// The `size` a Nano model is sent: [stored] when the model lists it, else
/// the listed value that matches the Studio's [studioSize], else the first
/// listed value that is not `auto`. Empty when the model lists none.
String remoteSizeFor(ImageModelInfo? model, String stored, String studioSize) {
  final listed = model?.resolutions ?? const <String>[];
  if (listed.isEmpty) return '';
  if (listed.contains(stored)) return stored;
  final want = remoteSizeLabel(studioSize);
  for (final value in listed) {
    if (remoteSizeLabel(value) == want) return value;
  }
  return listed.firstWhere(
    (v) => v.toLowerCase() != 'auto',
    orElse: () => listed.first,
  );
}

/// The xAI choices in display order with their labels.
List<(String, String)> xaiAspectChoices() => [
  for (final r in kXaiAspectRatios) (r, remoteSizeLabel(r)),
];
