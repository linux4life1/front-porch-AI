// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'realism_needs_tab.dart';

extension _GroupRealismNeedsEdits on _GroupRealismNeedsTabState {
  // ── Editable realism baseline update methods ──

  void _updateEditShortTermBond(CharacterCard char, int value) {
    final id = _getCharId(char);
    rebuildState(() {
      _editShortTermBond[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditLongTermBond(CharacterCard char, int value) {
    final id = _getCharId(char);
    rebuildState(() {
      _editLongTermBond[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditTrustLevel(CharacterCard char, int value) {
    final id = _getCharId(char);
    rebuildState(() {
      _editTrustLevel[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditEmotion(CharacterCard char, String value) {
    final id = _getCharId(char);
    rebuildState(() {
      _editEmotion[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _updateEditEmotionIntensity(CharacterCard char, String value) {
    final id = _getCharId(char);
    rebuildState(() {
      _editEmotionIntensity[id] = value;
    });
    _applyEditToBaselineSeedAndCard(char, id);
  }

  void _applyEditToBaselineSeedAndCard(CharacterCard char, String id) {
    final ext = char.frontPorchExtensions ?? FrontPorchExtensions();
    char.frontPorchExtensions = ext.copyWith(
      shortTermBond: _editShortTermBond[id] ?? 50,
      longTermBond: _editLongTermBond[id] ?? 50,
      trustLevel: _editTrustLevel[id] ?? 50,
      characterEmotion: _editEmotion[id] ?? 'neutral',
      emotionIntensity: _editEmotionIntensity[id] ?? 'moderate',
    );

    // Update the baseline seed via ChatService.
    try {
      widget.chatService.setBaselineSeedForGroupCharacter(char, {
        'affection': _editShortTermBond[id] ?? 50,
        'longTermScore': _editLongTermBond[id] ?? 50,
        'trust': _editTrustLevel[id] ?? 50,
        'emotion': _editEmotion[id] ?? 'neutral',
        'emotionIntensity': _editEmotionIntensity[id] ?? 'moderate',
      });
    } catch (_) {
      // Non-fatal
    }

    // Persist to group defaultMemberRealismState.
    try {
      final group = widget.chatService.activeGroup;
      if (group != null) {
        final map =
            group.defaultMemberRealismState.isNotEmpty &&
                group.defaultMemberRealismState != '{}'
            ? (jsonDecode(group.defaultMemberRealismState)
                      as Map<String, dynamic>? ??
                  {})
            : <String, dynamic>{};
        final perChar = (map['perChar'] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        final current = (perChar[id] as Map<String, dynamic>? ?? {})
            .cast<String, dynamic>();
        // ENGINE key names — the card-ext names written here before made four
        // of the five sliders a no-op (GroupMemberRealism reads only
        // affection/longTermScore/trust/emotion/emotionIntensity and passes
        // everything else through untouched).
        applyBaselineToMemberSeed(
          current,
          affection: _editShortTermBond[id] ?? 50,
          longTermScore: _editLongTermBond[id] ?? 50,
          trust: _editTrustLevel[id] ?? 50,
          emotion: _editEmotion[id] ?? 'neutral',
          emotionIntensity: _editEmotionIntensity[id] ?? 'moderate',
        );
        perChar[id] = current;
        map['perChar'] = perChar;
        group.defaultMemberRealismState = jsonEncode(map);
      }
    } catch (_) {
      // Non-fatal
    }
  }
}
