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

import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/utils/world_cover.dart';

/// The picture behind the chat: the Setting place's own cover, or the
/// nearest ancestor's when the place has none (a room shows its town).
///
/// Plain data; the desktop decodes [cover] once per change and the web
/// fetches it by [placeId] and [version], so neither surface carries the
/// bytes through every rebuild or every chat snapshot.
class SceneBackdrop {
  const SceneBackdrop({
    required this.placeId,
    required this.placeName,
    required this.cover,
  });

  /// The world whose picture this is (the Setting, or an ancestor).
  final String placeId;

  /// Display only: the dropdown's name for that place.
  final String placeName;

  /// The cover as the world row stores it: a `data:image/…;base64,` URL.
  final String cover;

  /// Changes when the picture does, so a re-saved cover busts the web's
  /// cache and the desktop's crossfade sees a new scene. The VM caches a
  /// string's hash, so this costs nothing after the first read.
  int get version => cover.hashCode;

  @override
  bool operator ==(Object other) =>
      other is SceneBackdrop &&
      other.placeId == placeId &&
      other.placeName == placeName &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(placeId, placeName, version);
}

/// The backdrop for a Setting's [chain] (leaf first, as
/// `WorldRepository.chainFor` returns it): the first place in it with a
/// stored cover picture, or null when none has one, in which case the chat
/// keeps its chosen background. A cover that is not an inlined data URL
/// (a path from an old import) never resolves to a file, so it counts as
/// none and the walk goes on to the parent.
SceneBackdrop? sceneBackdropOf(List<World> chain) {
  for (final world in chain) {
    final cover = world.coverImage;
    if (cover == null || !isWorldCoverDataUrl(cover)) continue;
    return SceneBackdrop(
      placeId: world.id,
      placeName: world.name,
      cover: cover.trim(),
    );
  }
  return null;
}

/// The relay route that serves a place's cover bytes to the PWA.
const String kSceneBackdropRoute = '/api/worlds/cover';

/// The chat state's `sceneBackdrop` for the web: who the picture belongs
/// to and where to fetch it. The URL carries the version so the browser
/// may cache it for good and still sees a new picture at once.
Map<String, Object> sceneBackdropWire(SceneBackdrop backdrop) => {
  'placeId': backdrop.placeId,
  'placeName': backdrop.placeName,
  'url':
      '$kSceneBackdropRoute?id=${Uri.encodeQueryComponent(backdrop.placeId)}'
      '&v=${backdrop.version}',
};

/// The raster types a cover may be served as. Anything else a data URL
/// declares (an SVG from a hand-made package, say) goes out as JPEG, which
/// a browser renders or rejects but never runs.
const Set<String> kSceneBackdropTypes = {
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
};

/// Splits a stored cover into its bytes and media type for the relay, or
/// null when it does not decode. The media type is read from the data URL
/// itself (`image/jpeg` for every cover the editor writes, `image/png` for
/// an imported one), falling back to JPEG.
({List<int> bytes, String contentType})? sceneBackdropBytes(String cover) {
  final bytes = decodeWorldCoverBytes(cover);
  if (bytes == null) return null;
  final head = cover.trimLeft();
  final semicolon = head.indexOf(';');
  var contentType = 'image/jpeg';
  if (head.startsWith('data:') && semicolon > 5) {
    final declared = head.substring(5, semicolon).trim().toLowerCase();
    if (kSceneBackdropTypes.contains(declared)) contentType = declared;
  }
  return (bytes: bytes, contentType: contentType);
}
