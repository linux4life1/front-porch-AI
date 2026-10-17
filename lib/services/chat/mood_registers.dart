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

import 'package:front_porch_ai/services/chat/group_member_realism.dart';
import 'package:front_porch_ai/services/chat/mood_effects.dart';
import 'package:front_porch_ai/services/chat/mood_physics.dart';
import 'package:front_porch_ai/services/chat/realism_scope.dart';

/// The one door to the live mood registers (label, intensity, cause, hold)
/// on the chat: every seed, stamp, restore, group load and save, judge apply
/// and easing goes through here, so the four fields can never drift apart
/// the way two of them used to be set in two lines at twenty sites.
class MoodRegisters {
  MoodRegisters(this._scope, {bool Function()? isTurnBusy})
    : _isTurnBusy = isTurnBusy;

  final RealismScope _scope;

  /// Whether a turn is running. Inside one, the pre-reply capture and the
  /// post-reply restamp carry a mood change onto the reply being written;
  /// only outside a turn does [set] have to patch the visible reply itself.
  /// Null (the dance, the snapshot, the settle) means never.
  final bool Function()? _isTurnBusy;

  MoodState get state => MoodState(
    label: _scope.emotion(),
    intensity: _scope.intensity(),
    cause: _scope.cause(),
    held: _scope.heldTurns(),
  );

  void _write(MoodState next) {
    _scope.setEmotion(next.label);
    _scope.setIntensity(next.intensity);
    _scope.setCause(next.cause);
    _scope.setHeldTurns(next.held);
  }

  /// Another feature moving the mood (the planner, objectives): a fresh
  /// feeling with a cause, hold 0. Outside a turn the visible reply's stamp
  /// is patched and the chat saved, so a swipe back still finds it; inside
  /// a turn the reply being written carries it (a pre-reply change rides the
  /// capture, a post-reply one the restamp), and patching the last accepted
  /// reply would hand a delete the new mood instead of the old. Listeners
  /// are told either way so the sidebar follows at once.
  void set(String label, String intensity, {String cause = ''}) {
    _write(
      MoodState(
        label: label.trim().toLowerCase(),
        intensity: intensity,
        cause: cleanMoodCause(cause),
      ),
    );
    if (!(_isTurnBusy?.call() ?? false)) {
      patchTipStamp();
      unawaited(_scope.saveChat());
    }
    _scope.notify();
  }

  /// Writes the live mood onto the visible reply's stamp. For a change made
  /// outside a turn (the today line's X): inside one, the capture and the
  /// post-reply restamp do this.
  void patchTipStamp() {
    for (final m in _scope.messages.reversed) {
      if (m.isUser || m.sender == 'System') continue;
      final rs = m.activeMetadata?['realism_state'];
      if (rs is Map && rs.containsKey(kMoodStampLabel)) {
        rs.addAll(state.toStamp());
      }
      return;
    }
  }

  /// A chevron or calendar day roll eased every mood at once: the latest
  /// reply of EACH speaker takes their eased mood, so a swipe or delete that
  /// restores any member's last stamp finds the mood after the roll. 1:1 is
  /// the tip alone.
  void patchLatestReplyStamps() {
    if (_scope.activeGroup() == null) {
      patchTipStamp();
      return;
    }
    final seen = <String>{};
    for (final m in _scope.messages.reversed) {
      if (m.isUser || m.sender == 'System') continue;
      final sid = m.characterId ?? '';
      if (sid.isEmpty || !seen.add(sid)) continue;
      final member = _scope.groups.members[sid];
      final rs = m.activeMetadata?['realism_state'];
      if (member != null && rs is Map && rs.containsKey(kMoodStampLabel)) {
        rs.addAll(memberMood(member).toStamp());
      }
      if (seen.length >= _scope.groups.members.length) return;
    }
  }

  void reset() => _write(MoodState.neutral);

  /// A card's authored starting mood or a greeting seed: no cause, no hold.
  void seed(String label, String intensity) =>
      _write(MoodState(label: label, intensity: intensity));

  /// Story days crossed: the live registers ease one step per day.
  void easeForDays(int days) => _write(easeMoodForDays(state, days));

  /// The day roll is chat-wide: every group member's stored mood eases, not
  /// only the one whose registers happen to be loaded.
  void easeMembersForDays(int days) {
    if (days <= 0) return;
    for (final member in _scope.groups.members.values) {
      final stored = memberMood(member);
      if (stored.isNeutral) continue;
      _writeMember(member, easeMoodForDays(stored, days));
    }
  }

  /// Restores from a reply's realism stamp the way label and intensity have
  /// always been restored: a missing key keeps the live value.
  void restoreFromStamp(Map<dynamic, dynamic>? stamp) =>
      _write(MoodState.fromStamp(stamp, state));

  /// Writes the four keys beside the other scalars in a stamp.
  void writeStamp(Map<String, dynamic> stamp) => stamp.addAll(state.toStamp());

  // ── Groups: the member record is the store, the registers are the loan ──

  static MoodState memberMood(GroupMemberRealism member) => MoodState(
    label: member.emotion ?? '',
    intensity: member.emotionIntensity ?? '',
    cause: member.emotionCause ?? '',
    held: member.emotionHeldTurns ?? 0,
  );

  static void _writeMember(GroupMemberRealism member, MoodState next) {
    member
      ..emotion = next.label
      ..emotionIntensity = next.intensity
      ..emotionCause = next.cause
      ..emotionHeldTurns = next.held;
  }

  /// The mood of a member who is not loaded (member cards, the phone).
  MoodState memberState(String charId) {
    final member = _scope.groups.members[charId];
    return member == null ? MoodState.neutral : memberMood(member);
  }

  /// Loads a member into the live registers before their turn. A member
  /// saved before cause and hold existed reads as a fresh feeling; one with
  /// no intensity on record reads moderate, as it always has.
  void loadFromMember(String charId) {
    final member = _scope.groups.members[charId];
    _write(
      MoodState(
        label: member?.emotion ?? '',
        intensity: member?.emotionIntensity ?? 'moderate',
        cause: member?.emotionCause ?? '',
        held: member?.emotionHeldTurns ?? 0,
      ),
    );
  }

  /// Saves the live registers back after the member's turn. An empty label
  /// is not saved unless [evenIfEmpty]: a first-turn member had none, and
  /// the record keeps whatever it had, exactly as before. A rewind that put
  /// an empty mood back passes [evenIfEmpty] so the record follows it.
  void saveToMember(String charId, {bool evenIfEmpty = false}) {
    final live = state;
    if (live.label.isEmpty && !evenIfEmpty) return;
    _writeMember(_scope.groups.memberForWrite(charId), live);
  }

  /// Another feature moving a member's mood while someone else may be
  /// loaded (a goal won or lost): a fresh feeling on the record, picked up
  /// at the member's next load.
  void setMember(String charId, MoodState next) {
    _writeMember(_scope.groups.memberForWrite(charId), next.copyWith(held: 0));
    _scope.notify();
  }

  /// A stamp's mood written straight onto a member record (a swipe or
  /// delete in a group puts the speaker's registers back without a load).
  void writeMemberFromStamp(String charId, Map<dynamic, dynamic> stamp) {
    final member = _scope.groups.memberForWrite(charId);
    _writeMember(member, MoodState.fromStamp(stamp, memberMood(member)));
  }

  /// `Furious (strong) · because he lied about the money · still`.
  String get displayLine => moodDisplayLine(state);
}
