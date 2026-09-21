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

part of 'create_group_chat_page.dart';

/// Roster mutations: add / remove / reorder / voice / realism seeds.
extension _GroupWizardRoster on _CreateGroupChatPageState {
  List<CharacterCard> get _availableCharacters {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final all = repo.characters;
    final memberIds = _members.map(_stableId).toSet();
    return all.where((c) => !memberIds.contains(_stableId(c))).toList();
  }
  // ── MEMBER MANAGEMENT (heart of the experience) ────────────────────

  void _addMember(CharacterCard card) {
    final id = _stableId(card);
    if (_members.any((m) => _stableId(m) == id)) return;
    rebuildState(() {
      _members.add(card);
      // Seed a reasonable neutral realism entry if none exists
      if (!_memberRealismSeeds.containsKey(id)) {
        _memberRealismSeeds[id] = _defaultRealismSeedFor(card);
      }
      if (!_memberNeedsBaselines.containsKey(id)) {
        final s = _memberRealismSeeds[id]!;
        _memberNeedsBaselines[id] = {
          'hunger': s['needsBaselineHunger'] as int? ?? 80,
          'bladder': s['needsBaselineBladder'] as int? ?? 80,
          'energy': s['needsBaselineEnergy'] as int? ?? 80,
          'social': s['needsBaselineSocial'] as int? ?? 80,
          'fun': s['needsBaselineFun'] as int? ?? 80,
          'hygiene': s['needsBaselineHygiene'] as int? ?? 80,
          'comfort': s['needsBaselineComfort'] as int? ?? 80,
          'decayHunger': s['needsDecayHunger'] as int? ?? 5,
          'decayBladder': s['needsDecayBladder'] as int? ?? 5,
          'decayEnergy': s['needsDecayEnergy'] as int? ?? 5,
          'decaySocial': s['needsDecaySocial'] as int? ?? 5,
          'decayFun': s['needsDecayFun'] as int? ?? 5,
          'decayHygiene': s['needsDecayHygiene'] as int? ?? 5,
          'decayComfort': s['needsDecayComfort'] as int? ?? 5,
        };
      }

      // Initialize empty relationships map for small groups
      if (_members.length <= 4) {
        final seed = _memberRealismSeeds[id]!;
        seed['relationships'] ??= <String, int>{};
      }

      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _members.map((c) => c.name).join(' & ');
      }
      _updateEstimates();
    });
  }

  void _removeMember(String id) {
    rebuildState(() {
      _members.removeWhere((c) => _stableId(c) == id);
      _characterVoices.remove(id);
      _characterSystemPrompts.remove(id);
      _memberRealismSeeds.remove(id);

      // Clean up any references to this member from other characters' relationship maps
      for (final seed in _memberRealismSeeds.values) {
        final rels = seed['relationships'];
        if (rels is Map) {
          rels.remove(id);
        }
      }

      if (_members.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = _members.map((c) => c.name).join(' & ');
      }
    });
  }

  // onReorderItem (unlike the retired onReorder) delivers newIndex already
  // adjusted for the removal at oldIndex — no manual decrement.
  void _reorderMembers(int oldIndex, int newIndex) {
    rebuildState(() {
      final moved = _members.removeAt(oldIndex);
      _members.insert(newIndex, moved);
    });
  }

  void _setVoice(String charId, String? voiceId) {
    rebuildState(() {
      _characterVoices[charId] = voiceId ?? '';
    });
  }

  // Shared default seed (create + edit parity) lives in group_realism_blobs.dart
  // as defaultGroupMemberRealismSeed(); the card arg is ignored (the seed is a
  // neutral constant) but kept so existing call sites read naturally.
  Map<String, dynamic> _defaultRealismSeedFor(CharacterCard c) =>
      defaultGroupMemberRealismSeed();

  void _seedRealismFromCard(String charId) {
    final card = _members.firstWhere(
      (c) => _stableId(c) == charId,
      orElse: () => _members.first,
    );
    rebuildState(() {
      _memberRealismSeeds[charId] = _defaultRealismSeedFor(card);
    });
  }

  void _bulkSeedRealism(String mode) {
    rebuildState(() {
      for (final c in _members) {
        final id = _stableId(c);
        if (mode == 'neutral') {
          _memberRealismSeeds[id] = _defaultRealismSeedFor(c);
        } else if (mode == 'highBond') {
          final s = _defaultRealismSeedFor(c);
          s['affection'] = 75;
          s['trust'] = 70;
          s['emotion'] = 'affection';
          s['emotionIntensity'] = 'moderate';
          _memberRealismSeeds[id] = s;
        }
      }
    });
  }
  // ── REALISM HELPERS ────────────────────────────────────────────────

  void _updateMemberRealism(String charId, Map<String, dynamic> values) {
    rebuildState(() {
      _memberRealismSeeds[charId] = {
        ...(_memberRealismSeeds[charId] ??
            _defaultRealismSeedFor(
              _members.firstWhere((c) => _stableId(c) == charId),
            )),
        ...values,
      };
    });
  }
}
