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

import 'dart:convert';

import 'package:front_porch_ai/models/avatar_image.dart';

/// Pure resolution for the per-character avatar GALLERY. Kept deliberately free
/// of I/O and of where the per-chat selection is STORED — it takes the selected
/// face id as an input — so it's trivially unit-testable.
///
/// Product contract (agreed with the maintainer + Grok): the avatar COLLECTION
/// is global per character; which face is SHOWING is per chat. In plain chat
/// (expression images off) the ‹ › chevrons cycle a FACE RING of the portrait +
/// the gallery looks + (when it's the ★ star) one expression image; chevrons
/// appear only when the ring has more than one entry. The one ★ star is the
/// canonical avatar — the ring's default entry, the card cover on export, AND
/// the home-grid/web library card cover (via coverImageFileFor) — and can
/// point at a look OR an expression. Selecting/starring never rewrites
/// `imagePath`; the only imagePath rewrite is deleting the portrait, which
/// promotes a look in its place (portrait_promotion.dart). The emotion
/// pipeline stays look-blind: a non-starred expression never enters the plain
/// ring, and a look is never picked as an emotion face.

/// The gallery looks among [avatarImages] (isLook), ordered by displayOrder.
/// Expression images are filtered out.
List<AvatarImage> looksFrom(List<AvatarImage>? avatarImages) =>
    (avatarImages ?? const <AvatarImage>[]).where((a) => a.isLook).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

/// The expression images among [avatarImages] (NOT looks). The emotion pipeline
/// must resolve through this so a gallery look can never be picked as an
/// expression (Grok must-fix: partition looks out of the expression system).
List<AvatarImage> expressionsFrom(List<AvatarImage>? avatarImages) =>
    (avatarImages ?? const <AvatarImage>[]).where((a) => !a.isLook).toList();

/// Sentinel face id for the character's library portrait (`imagePath`) inside
/// the plain-chat face ring / per-chat selection. A real avatar id references a
/// gallery look or (when starred) an expression image; this marks "the portrait".
const String kPortraitFaceId = '__portrait__';

/// Build the ordered plain-chat FACE RING the ‹ › chevrons cycle when expression
/// images are off. Entries are face ids: [kPortraitFaceId] for the portrait, or
/// an `avatar_images` id for a gallery look (or the starred expression).
///
/// Order = the star first (the default a new/unset chat shows), then the
/// portrait, then the gallery looks — deduped. The [favorite] (the resolved
/// starred row, or null for portrait/none) can be a look OR an expression: a
/// starred expression therefore joins the ring at slot 0, so it's BOTH the
/// default and reachable by chevron. Non-starred expressions never enter the
/// plain-chat ring (the display stays look-blind except for the one star the
/// user explicitly chose).
List<String> buildFaceRing({
  required List<AvatarImage> looks,
  required bool hasImagePath,
  AvatarImage? favorite,
}) {
  final ring = <String>[];
  void add(String id) {
    if (id.isNotEmpty && !ring.contains(id)) ring.add(id);
  }

  if (favorite != null) {
    add(favorite.id); // star leads (default face), look or expression
  } else if (hasImagePath) {
    add(kPortraitFaceId);
  }
  if (hasImagePath) add(kPortraitFaceId);
  for (final l in looks) {
    add(l.id);
  }
  return ring;
}

/// The next face id when flipping [ring] from [currentFaceId] by [delta]
/// (+1 next, -1 previous), wrapping. A current id that isn't in the ring (stale)
/// steps in from the appropriate end. Null only when the ring is empty.
String? flipFace(List<String> ring, String? currentFaceId, int delta) {
  if (ring.isEmpty) return null;
  final i = ring.indexOf(currentFaceId ?? '');
  if (i < 0) return delta >= 0 ? ring.first : ring.last;
  final n = ring.length;
  return ring[((i + delta) % n + n) % n];
}

/// What the plain-chat sidebar should show, resolved from the face [ring] + the
/// per-chat [selectedFaceId]. [allImages] is the character's full avatar list
/// (looks + expressions) used to resolve a face id to its image.
class FaceDisplay {
  /// The image to show, or null → the portrait (`imagePath`).
  final AvatarImage? image;

  /// 1-based position in the ring (for the "n / N" counter).
  final int position;

  /// Ring length (the N in "n / N").
  final int total;

  /// Whether to render the ‹ › chevrons (more than one face in the ring).
  final bool showChevrons;

  const FaceDisplay({
    required this.image,
    required this.position,
    required this.total,
    required this.showChevrons,
  });

  /// Nothing to override (no ring) — caller shows the portrait, no chevrons.
  static const FaceDisplay empty = FaceDisplay(
    image: null,
    position: 0,
    total: 0,
    showChevrons: false,
  );
}

/// Resolve the plain-chat face. The current face = [selectedFaceId] if it's
/// still in the ring, else the ring's first entry (the star / portrait / first
/// look) — a stale/deleted selection falls through instead of blanking the face.
/// [kPortraitFaceId] (or any id not found in [allImages]) resolves to the
/// portrait (null image).
FaceDisplay resolveFaceDisplay({
  required List<String> ring,
  required List<AvatarImage> allImages,
  String? selectedFaceId,
}) {
  if (ring.isEmpty) return FaceDisplay.empty;
  final current = (selectedFaceId != null && ring.contains(selectedFaceId))
      ? selectedFaceId
      : ring.first;
  AvatarImage? image;
  if (current != kPortraitFaceId) {
    for (final a in allImages) {
      if (a.id == current) {
        image = a;
        break;
      }
    }
  }
  return FaceDisplay(
    image: image,
    position: ring.indexOf(current) + 1,
    total: ring.length,
    showChevrons: ring.length > 1,
  );
}

/// Decode the per-chat look selection stored (JSON) in the session's
/// `selectedLookAvatarId` column into a `{characterId: lookAvatarId}` map.
///
/// The map (not a single id) is what lets a GROUP chat remember a distinct look
/// per participant while 1:1 is just a one-entry map — one code path, group
/// parity by construction (mirrors the existing `group_realism_state` house
/// style). Deliberately defensive: null / empty / malformed / non-map / bad
/// entries all collapse to an empty map and this NEVER throws, so a corrupt
/// column can't blank the portrait.
Map<String, String> decodeSelectedLooks(String? raw) {
  if (raw == null || raw.isEmpty) return <String, String>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return <String, String>{};
    final out = <String, String>{};
    decoded.forEach((k, v) {
      if (k is String && v is String && k.isNotEmpty && v.isNotEmpty) {
        out[k] = v;
      }
    });
    return out;
  } catch (_) {
    return <String, String>{};
  }
}

/// Encode the per-chat look selection map back to JSON for storage. An empty
/// map encodes to `null` so the column clears (never stores a bare `{}`).
String? encodeSelectedLooks(Map<String, String> selection) =>
    selection.isEmpty ? null : jsonEncode(selection);
