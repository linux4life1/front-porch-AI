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

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'package:front_porch_ai/models/avatar_image.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/avatar_gallery.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/portrait_promotion.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// How the Avatar Gallery was opened. Caller-passed (never inferred from global
/// state — Grok): [inChat] enables per-chat "use this look" selection and needs
/// a [ChatService]; [library] is management-only (from the home right-click).
enum WardrobeMode { library, inChat }

/// The single mutation surface + state for the unified Avatar Gallery. Every user
/// action goes through here: mutate → repository → reload → notify. The shell and
/// sections are dumb; this is the only place that touches the repo, so delete
/// cascades (clear the star / prime / this-chat selection) live in ONE spot.
///
/// Always operates on the ORIGIN LIBRARY card (the caller resolves group members
/// to their library origin), so the favorite, looks, expressions and per-chat
/// selection all key off the same library id the sidebar uses.
class AvatarGalleryController extends ChangeNotifier {
  AvatarGalleryController({
    required this.libraryCard,
    required this.repository,
    required this.storage,
    required this.mode,
    this.chat,
  });

  final CharacterCard libraryCard;
  final CharacterRepository repository;
  final StorageService storage;
  final WardrobeMode mode;

  /// Non-null only in [WardrobeMode.inChat].
  final ChatService? chat;

  static const int maxExpressions = 30;

  List<AvatarImage> looks = const [];
  List<AvatarImage> expressions = const [];

  /// The ★ canonical avatar id (a look or expression id), or null (= portrait).
  String? favoriteId;

  /// The prime (default) expression index (1-based `displayOrder + 1`).
  int primeIndex = 1;

  /// Draft emotion labels, flushed to the repo on Done (matches the old dialog).
  final Map<String, String> tempLabels = {};

  bool saving = false;

  /// Set when a repo call throws — the shell shows it then clears it.
  String? lastError;

  /// Whether the Expression images section is expanded (hide-rule).
  bool expressionsExpanded = false;

  /// Bumped whenever portrait bytes or gallery membership change so tiles with
  /// the same file path (in-place portrait overwrite after delete/bootstrap)
  /// drop their cached [Image.file] frames instead of showing a stale face.
  int mediaGen = 0;

  bool _disposed = false;

  void _bumpMedia() => mediaGen++;

  Future<void> _evictPortraitImage() async {
    final f = portraitFile();
    if (f != null) await FileImage(f).evict();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_needsCloseBroadcast) {
      // The star wrote silently per click (no repaint behind the dialog);
      // the home grid gets its ONE refresh now that the dialog is gone.
      // Deferred to a fresh event-loop task: dispose can run mid-frame, and
      // notifying the repo's listeners during build would assert. (This
      // controller stays widgets-import-free, hence no post-frame callback.)
      final repo = repository;
      Future(() => repo.notifyCharactersChanged());
    }
    super.dispose();
  }

  // Guard against the dialog closing while init()/a mutation future is still in
  // flight (would otherwise assert on a disposed ChangeNotifier).
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  String? get dbId => libraryCard.dbId;
  String? get portraitPath => libraryCard.imagePath;
  String get baseDirPath => storage.characterBaseDir(libraryCard.name).path;

  /// The face id showing in THIS chat (in-chat mode only), or null.
  String? get selectedFaceId => (mode == WardrobeMode.inChat && dbId != null)
      ? chat?.selectedLookFor(dbId!)
      : null;

  /// The library portrait file (`imagePath`), or null when unset.
  File? portraitFile() => portraitPath == null
      ? null
      : storage.resolveCharacterImage(portraitPath!);

  /// The on-disk file for a look or expression row (its `looks/` or `avatars/`).
  File fileFor(AvatarImage a) => a.resolveFile(baseDirPath);

  /// Load from the in-memory card immediately, then refresh from the repo.
  Future<void> init() async {
    _loadFromCard(libraryCard.avatarImages ?? const []);
    favoriteId = libraryCard.frontPorchExtensions?.favoriteAvatarId;
    primeIndex = libraryCard.primeAvatarIndex;
    expressionsExpanded = storage.expressionEnabled || expressions.isNotEmpty;
    notifyListeners();
    await _reload();
  }

  void _loadFromCard(List<AvatarImage> all) {
    looks = looksFrom(all);
    expressions = expressionsFrom(all);
    for (final e in expressions) {
      tempLabels.putIfAbsent(e.id, () => e.label ?? '');
    }
  }

  Future<void> _reload() async {
    if (dbId == null) return;
    final all = await repository.getAvatarImages(dbId!);
    _loadFromCard(all);
    // Keep the in-memory card fresh so the sidebar/home grid reflect changes
    // without a round-trip through the DB.
    libraryCard.avatarImages = all;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    saving = true;
    notifyListeners();
    try {
      await action();
    } catch (e) {
      lastError = '$e';
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  // ── The ★ star (immediate + serialized — a star lost on Cancel is worse than
  //    an extra write; Grok) ─────────────────────────────────────────────────
  Future<void> setFavorite(String? avatarId) => _run(() => _persistFavorite(avatarId));

  /// Persist [id] as the canonical avatar. Materializes the extensions object
  /// first (a null `frontPorchExtensions` would silently drop the write and the
  /// ★ would not survive a reopen — Grok P0). Silent write: broadcasting each
  /// click repainted the whole home grid behind the open dialog; [dispose]
  /// fires the one deferred broadcast instead.
  ///
  /// When the card has no usable portrait, `updateCharacter` would early-return
  /// and drop the ★ (imagePath is required for the PNG re-embed). Bootstrap a
  /// portrait from the starred image first so the write can land (issue #171).
  Future<void> _persistFavorite(String? id) async {
    favoriteId = id;
    (libraryCard.frontPorchExtensions ??= FrontPorchExtensions())
        .favoriteAvatarId = id;
    if (id != null && !hasUsablePortrait(libraryCard, storage)) {
      final img = looks.followedBy(expressions).where((a) => a.id == id).firstOrNull;
      if (img != null) {
        final file = fileFor(img);
        if (await file.exists()) {
          await bootstrapPortraitIfMissing(
            card: libraryCard,
            storage: storage,
            bytes: await file.readAsBytes(),
            updateCharacter: (c) => repository.updateCharacter(c, notify: false),
          );
          await _evictPortraitImage();
          _bumpMedia();
          _needsCloseBroadcast = true;
          return;
        }
      }
    }
    await repository.updateCharacter(libraryCard, notify: false);
    _needsCloseBroadcast = true;
  }

  /// Set when a silent write happened; the dialog-close broadcast is owed.
  bool _needsCloseBroadcast = false;

  // ── Gallery avatars ─────────────────────────────────────────────────────────
  Future<void> addLook(Uint8List bytes) => _run(() async {
    if (dbId == null) return;
    await repository.addLook(dbId!, libraryCard.name, bytes);
    // addLook may bootstrap a missing portrait onto the in-memory card;
    // re-sync imagePath so the Portrait tile appears without reopening.
    final fresh = await repository.getCharacterCardById(dbId!);
    if (fresh?.imagePath != null) libraryCard.imagePath = fresh!.imagePath;
    await _evictPortraitImage();
    _bumpMedia();
    await _reload();
    // Cover / portrait may have changed (bootstrap); home refreshes on close.
    _needsCloseBroadcast = true;
  });

  /// In-chat only: show [faceId] (a look id or [kPortraitFaceId]) in this chat.
  Future<void> selectFaceInChat(String? faceId) async {
    if (mode != WardrobeMode.inChat || dbId == null) return;
    await chat?.setLookForCharacter(dbId!, faceId);
    notifyListeners();
  }

  /// Replace the canonical portrait (imagePath) with an already-cropped file.
  Future<void> replacePortrait(String croppedPath) => _run(() async {
    await repository.setCharacterImagePath(libraryCard, croppedPath);
    await _evictPortraitImage();
    _bumpMedia();
    _needsCloseBroadcast = true;
  });

  /// Delete the portrait — the ★ starred look (else the first) is promoted
  /// in its place. The UI hides this affordance when no looks exist.
  Future<void> deletePortrait() => _run(() async {
    if (dbId == null) return;
    final promotedId = await repository.deletePortraitPromotingLook(
      libraryCard,
    );
    favoriteId = libraryCard.frontPorchExtensions?.favoriteAvatarId;
    // Same hygiene as remove(): this chat was showing the promoted look →
    // clear the per-chat selection (it now lives on as the portrait).
    if (mode == WardrobeMode.inChat && selectedFaceId == promotedId) {
      await chat?.setLookForCharacter(dbId!, null);
    }
    // Same path, new pixels — evict + bump so the Portrait tile reloads
    // instead of keeping the deleted face while the promoted look vanishes.
    await _evictPortraitImage();
    _bumpMedia();
    await _reload();
    _needsCloseBroadcast = true;
  });

  // ── Expression images ───────────────────────────────────────────────────────
  Future<void> addExpression(Uint8List bytes, String? emotion) => _run(() async {
    if (dbId == null || expressions.length >= maxExpressions) return;
    await repository.addAvatar(dbId!, libraryCard.name, bytes, emotion);
    await _reload();
  });

  /// Import an emotion-named ZIP sprite pack. Returns (added, unrecognized,
  /// skippedForCap) for the caller's snackbar.
  Future<(int, int, int)> importSpritePack(
    List<({Uint8List bytes, String emotion})> entries,
    int unrecognized,
  ) async {
    if (dbId == null) return (0, unrecognized, 0);
    var added = 0;
    var skippedForCap = 0;
    await _run(() async {
      for (final e in entries) {
        if (expressions.length + added >= maxExpressions) {
          skippedForCap++;
          continue;
        }
        await repository.addAvatar(dbId!, libraryCard.name, e.bytes, e.emotion);
        added++;
      }
      if (added > 0) await _reload();
    });
    return (added, unrecognized, skippedForCap);
  }

  Future<void> setPrime(AvatarImage expr) => _run(() async {
    if (dbId == null) return;
    primeIndex = expr.displayOrder + 1;
    await repository.setPrimeAvatar(dbId!, primeIndex);
    libraryCard.primeAvatarIndex = primeIndex;
  });

  void setLabelDraft(String avatarId, String label) {
    tempLabels[avatarId] = label;
    notifyListeners();
  }

  // ── Delete (with all cascades in one place — Grok) ──────────────────────────
  Future<void> remove(AvatarImage img) => _run(() async {
    if (dbId == null) return;
    // Evict before the file is gone so the ImageCache drops this path.
    await FileImage(fileFor(img)).evict();
    await repository.removeAvatar(dbId!, img.id);
    // Star pointed at it → back to the portrait (materializes ext + persists).
    if (favoriteId == img.id) await _persistFavorite(null);
    // This chat was showing it → clear the per-chat selection (falls back to
    // the star/portrait; the resolver also degrades stale ids, this is hygiene).
    if (mode == WardrobeMode.inChat && selectedFaceId == img.id) {
      await chat?.setLookForCharacter(dbId!, null);
    }
    _bumpMedia();
    await _reload();
    // Prime pointed at a now-deleted expression → first remaining (or reset to
    // 1 when none remain). Always persist so the DB can't keep a dangling prime.
    if (!expressions.any((e) => e.displayOrder + 1 == primeIndex)) {
      primeIndex = expressions.isNotEmpty ? expressions.first.displayOrder + 1 : 1;
      libraryCard.primeAvatarIndex = primeIndex;
      await repository.setPrimeAvatar(dbId!, primeIndex);
    }
    _needsCloseBroadcast = true;
  });

  /// Flush the drafted emotion labels + prime index. Called on Done. Routed
  /// through [_run] so a failed label write surfaces as [lastError] instead of
  /// throwing out of the Done handler (Grok).
  Future<void> flushOnDone() => _run(() async {
    if (dbId == null) return;
    for (final e in expressions) {
      final label = tempLabels[e.id] ?? '';
      if (label != e.label) {
        await repository.updateAvatarLabel(e.id, label);
      }
    }
    libraryCard.primeAvatarIndex = primeIndex;
    await _reload();
  });
}
