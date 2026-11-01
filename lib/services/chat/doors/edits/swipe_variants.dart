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

import 'dart:async';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/doors/edits/edit_deps.dart';
import 'package:front_porch_ai/services/chat/doors/edits/regen_controller.dart';
import 'package:front_porch_ai/services/macro_resolver.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// Swipes and the variant picker: chevrons, a picked regen swipe, and the
/// opening greet picker that shares the dialog.
///
/// A TIP swipe restores that swipe's snapshot (Realism, Pockets, the clock)
/// and rewrites the timeline after it, Journal and Growth alike; a buried
/// swipe is navigation. In a group the restore goes into the swiped
/// speaker's own entry.
class SwipeVariants {
  SwipeVariants(this._d, this._regen);

  final EditDeps _d;
  final RegenController _regen;

  ChatSessionState get _session => _d.session;
  EditServices get _s => _d.services;
  EditsView get _v => _d.view;
  late final RealismScope _scope = _s.realismScope();
  GroupChat? get _activeGroup => _session.activeGroup;
  bool get _realismEnabled => _scope.realismEnabled();

  String _getCharacterIdFromCard(CharacterCard c) => _d.characterIdFor(c);
  bool _isGuestAuthoredMessage(ChatMessage m) => _d.cast.isGuestAuthored(m);
  Future<void> _saveChat() => _d.saveChat();
  void notifyListeners() => _d.notify();

  /// Navigate swipes on a specific message. direction: -1 = left, +1 = right.
  /// If swiping right past the last swipe on the last bot message, regenerates.
  Future<void> swipeMessage(
    int messageIndex,
    int direction, {
    String? critique,
  }) async {
    if (messageIndex < 0 || messageIndex >= _session.messages.length) return;
    final msg = _session.messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;

    final newIndex = msg.swipeIndex + direction;

    if (direction < 0) {
      if (newIndex >= 0) {
        await _commitSwipeIndex(messageIndex, newIndex);
      }
      return;
    }

    if (newIndex < msg.swipes.length) {
      await _commitSwipeIndex(messageIndex, newIndex);
    } else if (messageIndex == _session.messages.length - 1) {
      // Past last swipe on last message — regenerate (aborts settling evals)
      await _regen.regenerateLastMessage(critique: critique);
    }
  }

  /// Apply an already-stored swipe index. Host tip restores the speaker
  /// snapshot. A last-in-chat guest swipe restores the host wear that
  /// beat left (guest replies have no speaker Realism of their own).
  /// Buried swipes are navigation, not time travel.
  Future<void> _commitSwipeIndex(int messageIndex, int newIndex) async {
    final msg = _session.messages[messageIndex];
    if (newIndex == msg.swipeIndex) return;
    if (newIndex < 0 || newIndex >= msg.swipes.length) return;

    final isGuestMsg = _isGuestAuthoredMessage(msg);
    final isTip =
        !isGuestMsg &&
        _session.messages.skip(messageIndex + 1).every(_isGuestAuthoredMessage);
    final isGuestTip =
        isGuestMsg && messageIndex == _session.messages.length - 1;

    msg.swipeIndex = newIndex;
    if (isTip || isGuestTip) {
      _s.clockReader().applyTipClock();
    }
    if (isTip) _syncRealismStateForSwipe(msg);
    if (isGuestTip) {
      _s.needsRewinds().restoreWornBodiesExceptSpeaker(
        msg,
        msg.characterId ?? '',
      );
    }
    // Pockets follow the selected variant too — this swipe's own
    // post-turn record, or the shared pre-turn base when this variant's
    // pass changed nothing (hostile review 2026-08-11).
    if (isTip) _s.pocketsRewinds().restoreFromStamp(msg, after: true);
    // Timeline integrity follows the same tip-only rule pockets/realism
    // already use. A TIP swipe is a suffix rewrite: Journal/Growth/RAG
    // citing this position and later describe events that no longer
    // happened, then this variant's item cards are re-sown. A buried
    // swipe is navigation — later memories stay on screen AND in the
    // diary; only this variant's item cards are re-sown.
    if (isTip) {
      _s.timeline().invalidateFrom(
        persistMessagePosition(
          base: _s.history().basePosition,
          index: messageIndex,
        ),
        thenReplantPlanted: msg,
      );
    } else {
      unawaited(_s.itemCards().replant(msg, key: 'item_cards_planted'));
    }
    await _saveChat();
    notifyListeners();
  }

  void _syncRealismStateForSwipe(ChatMessage msg) {
    if (!_realismEnabled) return;

    // Natively restore the frozen runtime variables for the selected alternate
    // timeline — in groups, into the swiped speaker's own _groupRealism entry.
    _d.realism.restoreForSpeaker(msg, restoreClock: false);
    final speaker = resolveGroupSpeakerForMessage(
      _session.groupCharacters,
      msg,
    );
    if (_activeGroup != null && speaker != null) {
      _s.needsRewinds().restoreWornBodiesExceptSpeaker(
        msg,
        _getCharacterIdFromCard(speaker),
      );
    }
  }

  /// The card whose greets the opening picker cycles. Read through the
  /// public view (and so answerable by a golden double) — groups have a
  /// null active character even when the opener is a member greet.
  List<String> get openingAllGreetings {
    if (_v.isGroupMode()) {
      final g = _v.activeGroup();
      if (g != null && !greetingFirstMesEmpty(g.firstMessage)) {
        return g.allGreetings;
      }
      final messages = _v.messages();
      if (messages.isEmpty) return const [];
      final cid = messages.first.characterId;
      if (cid == null || cid.isEmpty) return const [];
      for (final c in _v.groupCharacters()) {
        if (_getCharacterIdFromCard(c) == cid || c.stableGroupId == cid) {
          return c.allGreetings;
        }
      }
      return const [];
    }
    return _v.activeCharacter()?.allGreetings ?? const [];
  }

  /// True when this bubble is the opening greet with more than one card greet
  /// and no stored regen swipes (those are variants, not greets).
  bool isSelectableGreeting(int messageIndex) {
    // The public view, so a golden double can answer this from a bubble
    // build.
    final messages = _v.messages();
    if (messageIndex < 0 || messageIndex >= messages.length) return false;
    final msg = messages[messageIndex];
    return usesGreetingPicker(
      messageIndex: messageIndex,
      isUser: msg.isUser,
      greetCount: openingAllGreetings.length,
      swipeCount: msg.swipes.length,
      userHasReplied: messages.any((m) => m.isUser),
    );
  }

  /// Picker rows for [messageIndex]. Card greets are macro-resolved so the
  /// preview reads like the opening bubble, not `{{char}}` + HTML comments.
  List<VariantOption> variantsForMessage(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _v.messages().length) {
      return const [];
    }
    if (isSelectableGreeting(messageIndex)) {
      return buildVariantOptions(
        resolvedOpeningGreetings(),
        _v.greetingIndex(),
        kind: VariantKind.greet,
      );
    }
    final msg = _v.messages()[messageIndex];
    return buildVariantOptions(
      msg.swipes,
      msg.swipeIndex,
      kind: VariantKind.regen,
    );
  }

  Map<String, dynamic> variantPickerPayload(int messageIndex) {
    if (messageIndex < 0 || messageIndex >= _v.messages().length) {
      return {
        'kind': 'regen',
        'title': 'Select variant',
        'currentIndex': 0,
        'variants': const [],
      };
    }
    final greet = isSelectableGreeting(messageIndex);
    final options = variantsForMessage(messageIndex);
    final current = options.where((v) => v.isCurrent);
    return {
      'kind': greet ? 'greet' : 'regen',
      'title': greet ? 'Select greet' : 'Select variant',
      'currentIndex': current.isEmpty ? 0 : current.first.index,
      'variants': [for (final v in options) v.toJson()],
    };
  }

  /// The opening greets as the bubble shows them, macro-resolved: a custom
  /// group greeting's alts, else the greeting owner's card greets.
  List<String> resolvedOpeningGreetings() {
    if (_activeGroup != null &&
        !greetingFirstMesEmpty(_activeGroup!.firstMessage)) {
      return [
        for (final g in _activeGroup!.allGreetings)
          _s.macroResolver().resolve(
            g,
            MacroContext(userName: _s.personas().persona.name),
            section: 'greeting',
          ),
      ];
    }
    final character = _d.cast.greetingOwner() ?? _session.activeCharacter;
    if (character == null) return const [];
    return [
      for (final g in character.allGreetings)
        _d.cast.firstMessage(character, greetingText: g),
    ];
  }

  /// Commit one greet. Opening-only chats re-apply that greet's authored
  /// Realism/Needs seed (or read-the-room when the alt has none). Swiping
  /// back to index 0 restores the card/group base — it does not keep the
  /// previous alt's live mood. Re-selecting the same index is a no-op.
  Future<void> selectGreeting(int index) async {
    if (_session.messages.isEmpty) return;
    final allGreetings = openingAllGreetings;
    if (allGreetings.length <= 1) return;
    if (index < 0 || index >= allGreetings.length) return;
    if (index == _d.cast.greetingIndex()) return;

    await _d.cast.invalidateGreetingEval();

    _d.cast.setGreetingIndex(index);
    final resolved = resolvedOpeningGreetings();
    if (index >= resolved.length) return;
    final old = _session.messages[0];
    final groupCustom =
        _activeGroup != null &&
        !greetingFirstMesEmpty(_activeGroup!.firstMessage);
    _session.messages[0] = ChatMessage(
      text: resolved[index],
      sender: groupCustom ? _activeGroup!.name : (old.sender),
      isUser: false,
      characterId: groupCustom ? null : old.characterId,
    );
    _d.cast.stampGreetingIndex(index);

    if (_d.cast.isOpeningGreetingChat()) {
      if (groupCustom) {
        await _d.cast.seedGroupGreeting(index);
      } else {
        final owner = _d.cast.greetingOwner() ?? _session.activeCharacter;
        if (owner != null) {
          await _d.cast.seedGreeting(card: owner, index: index);
        }
      }
    }

    await _saveChat();
    notifyListeners();
  }

  /// Jump to an already-stored swipe. Never generates a new one (the
  /// chevron-past-the-end path in [swipeMessage] still does). Restores
  /// that swipe's snapshot when this message is the tip — no reading-the-room.
  Future<void> selectSwipe(int messageIndex, int swipeIndex) async {
    if (messageIndex < 0 || messageIndex >= _session.messages.length) return;
    final msg = _session.messages[messageIndex];
    if (msg.isUser || msg.sender == 'System') return;
    await _commitSwipeIndex(messageIndex, swipeIndex);
  }

  Future<void> selectVariant(int messageIndex, int variantIndex) async {
    if (isSelectableGreeting(messageIndex)) {
      await selectGreeting(variantIndex);
    } else {
      await selectSwipe(messageIndex, variantIndex);
    }
  }
}
