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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/web/facade/group_member_seed.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// What the web's new-group wizard posts beyond name, members, turn order
/// and worlds: the Identity switches with each member's Voice, the Opening,
/// Realism (with Group Dynamics) and Prompts & Lore, as the desktop wizard
/// collects them.
///
/// Every field is optional and read defensively, since phones and desktops
/// run mixed versions: a body with none of them gets Realism and Needs on,
/// every member starting from their card.
/// Member keys are library character ids; the facade maps them to the new
/// member ids with [realismBlobs] and [promptsFor].
class GroupCreateDraft {
  GroupCreateDraft.fromBody(Map<String, dynamic> body)
    : autoAdvance = body['autoAdvance'] == true,
      directorMode = body['directorMode'] == true,
      inheritCharacterLorebooks = body['inheritCharacterLorebooks'] == true,
      chaosModeEnabled = body['chaosModeEnabled'] == true,
      chaosNsfwEnabled = body['chaosNsfwEnabled'] == true,
      scenario = _text(body['scenario']),
      firstMessage = _text(body['firstMessage']),
      memberPrompts = _stringMap(body['memberPrompts']),
      memberVoices = {
        for (final e in _stringMap(body['memberVoices']).entries)
          e.key: e.value.trim(),
      },
      groupLore = _lore(body['groupLore']),
      greetings = compactGreetingPairs(
        greetingSlotsFromRaw(body['alternateGreetings']),
        parseGreetingSeeds(body['greetingSeeds']),
      ),
      _realism = body['realism'] is Map
          ? Map<String, dynamic>.from(body['realism'] as Map)
          : const {};

  final bool autoAdvance;
  final bool directorMode;
  final bool inheritCharacterLorebooks;

  /// Group Chaos (Chance Time) and its adult events, as the desktop wizard
  /// stores them: independent of Realism.
  final bool chaosModeEnabled;
  final bool chaosNsfwEnabled;
  final String scenario;
  final String firstMessage;

  /// Library id → that member's extra instructions in this group.
  final Map<String, String> memberPrompts;

  /// Library id → the Voice picked for that member: a voice id, or '' for
  /// the global voice. A member with no entry keeps the card's own voice
  /// (see memberVoiceFromPick).
  final Map<String, String> memberVoices;
  final List<LorebookEntry> groupLore;

  /// Alternate openings and their realism seeds, paired as the editor does.
  final ({List<String> greetings, List<GreetingRealismSeed?> seeds}) greetings;
  final Map<String, dynamic> _realism;

  bool get realismEnabled => _realism['enabled'] != false;
  bool get needsEnabled => _realism['needsEnabled'] != false;

  /// How the group's new chats start Afterglow; an older phone sends none.
  bool get afterglowEnabled => _realism['afterglow'] != false;

  String get timeOfDay {
    final t = _realism['timeOfDay'];
    return t is String && StoryClock.periods.contains(t) ? t : 'morning';
  }

  int get dayCount {
    final d = _realism['dayCount'];
    return d is num && d >= 1 ? d.toInt() : 1;
  }

  /// Story Calendar start ("YYYY-MM-DD"); null is the day the chat starts.
  String? get storyStartDate {
    final v = _realism['storyStartDate'];
    return v is String && StoryClock.parse(v.trim()) != null ? v.trim() : null;
  }

  /// Exact opening clock ("HH:MM"); null is the time of day's default.
  String? get storyStartTime {
    final v = _realism['storyStartTime'];
    return v is String && StoryClock.parseHHMM(v) != null ? v.trim() : null;
  }

  /// The FrontPorchExtensions JSON for [source]'s new member row, built as
  /// the desktop committer builds it. Only the fields the body posted for
  /// this member override the card's own, so an old body keeps them.
  String? memberExtensionsJson(CharacterCard source) {
    final fp = groupMemberExtensions(
      source,
      memberSeedOverrides(_realism['members'], source.dbId),
      realismEnabled: realismEnabled,
    );
    return fp == null ? null : jsonEncode(fp.toJson());
  }

  /// The realism blobs for the group, keyed by the member ids [idMap] maps
  /// the [sources]' library ids to. Each member starts from their card's
  /// seed with what was posted for it laid over, as the desktop committer
  /// does; Group Dynamics rides along for groups of four or fewer. Null
  /// when Realism is off, which stores the empty blobs.
  GroupRealismBlobs? realismBlobs(
    Iterable<CharacterCard> sources,
    Map<String, String> idMap,
  ) {
    if (!realismEnabled) return null;
    final rels = _realism['relationships'] is Map
        ? _realism['relationships'] as Map
        : const {};
    final seeds = <String, Map<String, dynamic>>{};
    for (final source in sources) {
      final libId = source.dbId;
      if (libId == null || !idMap.containsKey(libId)) continue;
      final seed = groupMemberStartingSeed(
        source.frontPorchExtensions,
        memberSeedOverrides(_realism['members'], libId),
      );
      final r = rels[libId];
      seed['relationships'] = <String, int>{
        if (idMap.length <= 4 && r is Map)
          for (final e in r.entries)
            if (e.value is num && idMap.containsKey(e.key) && e.key != libId)
              e.key.toString(): (e.value as num).toInt().clamp(-300, 300),
      };
      seeds[libId] = seed;
    }
    return buildGroupRealismBlobs(
      seeds: remapSeedsToMemberIds(seeds, idMap),
      needsEnabled: needsEnabled,
      afterglowEnabled: afterglowEnabled,
      timeOfDay: timeOfDay,
      dayCount: dayCount,
      storyStartDate: storyStartDate,
      storyStartTime: storyStartTime,
    );
  }

  /// [memberPrompts] re-keyed to member ids, blanks dropped.
  Map<String, String> promptsFor(Map<String, String> idMap) => {
    for (final e in memberPrompts.entries)
      if (idMap[e.key] case final mid? when e.value.trim().isNotEmpty)
        mid: e.value.trim(),
  };

  /// The group lorebook as stored; empty when there are no entries.
  String get lorebookJson => groupLore.isEmpty
      ? ''
      : jsonEncode(Lorebook(entries: groupLore).toJson());

  static String _text(Object? v) => v is String ? v.trim() : '';

  static Map<String, String> _stringMap(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            if (e.value is String) e.key.toString(): e.value as String,
        }
      : const {};

  static List<LorebookEntry> _lore(Object? v) => [
    if (v is List)
      for (final e in v)
        if (e is Map && _text(e['content']).isNotEmpty)
          LorebookEntry(
            name: _text(e['name']),
            keys: [
              for (final k
                  in (e['keys'] is List ? e['keys'] as List : const []))
                if (k is String && k.trim().isNotEmpty) k.trim(),
            ],
            content: _text(e['content']),
            constant: e['constant'] == true,
            enabled: e['enabled'] != false,
          ),
  ];
}
