// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'image_gen_types.dart';
import 'image_studio_remote.dart';
import 'remote_studio_copy.dart';
import 'xai_image.dart';

/// One host tile on the Remote panel.
class RemoteHostTile {
  const RemoteHostTile({
    required this.host,
    required this.sub,
    required this.selected,
    required this.usable,
  });

  final ImageStudioRemoteHost host;
  final String sub;
  final bool selected;

  /// A key is saved or the person is signed in.
  final bool usable;

  Map<String, Object> toJson() => {
    'id': host.id,
    'label': host.label,
    'url': host.url,
    'sub': sub,
    'selected': selected,
    'hasKey': usable,
  };
}

/// A size, ratio or resolution pill: the value sent and what it reads.
class RemoteChoice {
  const RemoteChoice(this.value, this.label, {required this.selected});

  final String value;
  final String label;
  final bool selected;

  Map<String, Object> toJson() => {
    'value': value,
    'label': label,
    'selected': selected,
  };
}

enum RemoteSizeMode { pixels, xai, none }

/// Everything Image Studio's Remote panel shows, judged once so the desktop
/// panel and the phone show the same thing.
class RemoteStudioPanel {
  RemoteStudioPanel._({
    required this.tiles,
    required this.host,
    required this.url,
    required this.billing,
    required this.needsKey,
    required this.reachable,
    required this.status,
    required this.model,
    required this.modelId,
    required this.badges,
    required this.price,
    required this.sizeMode,
    required this.sizes,
    required this.resolutions,
    required this.sizeNote,
  });

  factory RemoteStudioPanel.build({
    required String selectedUrl,
    required bool Function(String url) hasKey,
    required bool Function(String url) signedIn,
    required List<ImageModelInfo> models,
    required bool listed,
    required String modelId,
    required String storedSize,
    required String studioSize,
    required String xaiAspect,
    required String xaiResolution,
  }) {
    // A custom address (chat's own, never picked here) selects no tile; the
    // panel still names and bills that address. No address at all is the
    // first host, which is what the panel shows and a saved key goes to.
    final known =
        imageRemoteHostFor(selectedUrl) ??
        (selectedUrl.trim().isEmpty ? kImageStudioRemoteHosts.first : null);
    final host = known ?? kImageStudioRemoteHosts.first;
    final url = known == null && selectedUrl.isNotEmpty
        ? selectedUrl
        : host.url;
    final tiles = [
      for (final h in kImageStudioRemoteHosts)
        RemoteHostTile(
          host: h,
          sub: RemoteStudioCopy.hostSub(
            signedIn: signedIn(h.url),
            hasKey: hasKey(h.url),
          ),
          selected: known != null && h.id == host.id,
          usable: hasKey(h.url) || signedIn(h.url),
        ),
    ];
    final usable = hasKey(url) || signedIn(url);
    ImageModelInfo? model;
    for (final m in models) {
      if (m.id == modelId) model = m;
    }
    if (model == null && modelId.isNotEmpty) {
      model = ImageModelInfo(id: modelId);
    }
    final sizeMode = switch (host.id) {
      'xai' => RemoteSizeMode.xai,
      'openrouter' => RemoteSizeMode.none,
      _ => RemoteSizeMode.pixels,
    };
    final aspect = xaiAspectOrSize(xaiAspect, studioSize);
    final resolution = xaiResolutionOr(xaiResolution);
    final size = remoteSizeFor(model, storedSize, studioSize);
    final sizes = switch (sizeMode) {
      RemoteSizeMode.xai => [
        for (final (value, label) in xaiAspectChoices())
          RemoteChoice(value, label, selected: value == aspect),
      ],
      RemoteSizeMode.pixels => [
        for (final value in model?.resolutions ?? const <String>[])
          RemoteChoice(value, remoteSizeLabel(value), selected: value == size),
      ],
      RemoteSizeMode.none => const <RemoteChoice>[],
    };
    return RemoteStudioPanel._(
      tiles: tiles,
      host: host,
      url: url,
      billing: known == null
          ? 'Bills your Remote API account (${Uri.tryParse(url)?.host ?? url}) '
                'per image.'
          : RemoteStudioCopy.billing(host, signedIn: signedIn(url)),
      needsKey: !usable,
      reachable: listed,
      status: listed
          ? RemoteStudioCopy.status(host, models.length)
          : models.isEmpty
          ? 'Not reachable'
          : 'Not reachable · showing the app’s own model list',
      model: model,
      modelId: modelId,
      badges: model == null ? const [] : RemoteStudioCopy.badges(host, model),
      price: model == null
          ? ''
          : RemoteStudioCopy.price(host, model, size: size),
      sizeMode: sizeMode,
      sizes: sizes,
      resolutions: [
        for (final r in kXaiResolutions)
          RemoteChoice(r, r, selected: r == resolution),
      ],
      sizeNote: switch (sizeMode) {
        RemoteSizeMode.xai => RemoteStudioCopy.sizeNote(
          host,
          model,
          aspect: aspect,
          resolution: resolution,
        ),
        RemoteSizeMode.pixels =>
          sizes.isEmpty
              ? 'This model lists no sizes. Nano-GPT picks one.'
              : RemoteStudioCopy.sizeNote(host, model),
        RemoteSizeMode.none => RemoteStudioCopy.openRouterSize,
      },
    );
  }

  final List<RemoteHostTile> tiles;
  final ImageStudioRemoteHost host;
  final String url;
  final String billing;
  final bool needsKey;
  final bool reachable;
  final String status;
  final ImageModelInfo? model;
  final String modelId;
  final List<String> badges;
  final String price;
  final RemoteSizeMode sizeMode;
  final List<RemoteChoice> sizes;
  final List<RemoteChoice> resolutions;
  final String sizeNote;

  String get keyPrompt => RemoteStudioCopy.keyPrompt(host);
  String get keyHint => RemoteStudioCopy.keyHint(host);
  String get keyNote => RemoteStudioCopy.keyNote;
  String get needsKeyLine => RemoteStudioCopy.needsKey(host);
  String get sizeTitle => RemoteStudioCopy.sizeTitle(host);
  String get modelName => model?.displayName ?? 'No model chosen';

  Map<String, Object?> toJson() => {
    'hosts': [for (final t in tiles) t.toJson()],
    'hostId': host.id,
    'hostLabel': host.label,
    'url': url,
    'billing': billing,
    'needsKey': needsKey,
    'keyPrompt': keyPrompt,
    'keyHint': keyHint,
    'keyNote': keyNote,
    'needsKeyLine': needsKeyLine,
    'reachable': reachable,
    'status': status,
    'modelName': modelName,
    'modelId': modelId,
    'badges': badges,
    'price': price,
    'sizeMode': sizeMode.name,
    'sizeTitle': sizeTitle,
    'sizes': [for (final c in sizes) c.toJson()],
    'resolutions': [for (final c in resolutions) c.toJson()],
    'sizeNote': sizeNote,
  };
}
