// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'realism_needs_tab.dart';

extension _GroupRealismNeedsToggles on _GroupRealismNeedsTabState {
  Widget _sliderRow(
    String label,
    int value,
    int min,
    int max,
    String tierName,
    Color color,
    ValueChanged<int> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
              ),
              child: Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: max - min > 0 ? (max - min) ~/ 10 : 0,
                label: value.toString(),
                onChanged: (d) => onChanged(d.round()),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: Text(
              value.toString(),
              style: TextStyle(fontSize: 10, color: color),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  void _updateRealism(bool value) {
    rebuildState(() {
      _realismEnabled = value;
    });
    widget.chatService.setRealismEnabled(value);
  }

  void _updatePassageOfTime(bool value) {
    rebuildState(() {
      _passageOfTimeEnabled = value;
    });
    // Through the ChatService wrapper (saves + notifies) — the raw
    // TimeService setter is side-effect-free, so the old direct call never
    // persisted the toggle beyond this dialog's local state.
    widget.chatService.setPassageOfTimeEnabled(value);
  }

  void _updateChaosMode(bool value) {
    rebuildState(() {
      _chaosModeEnabled = value;
    });
    // ChatService wrapper — saves + notifies (the raw service does neither).
    widget.chatService.setChaosModeEnabled(value);
  }

  void _updateChaosNsfw(bool value) {
    rebuildState(() {
      _chaosNsfwEnabled = value;
    });
    widget.chatService.setChaosNsfwEnabled(value);
  }

  void _updateNsfwEnhancements(bool value) {
    rebuildState(() {
      _nsfwEnhancementsEnabled = value;
    });
    // Same setter the sidebar gear uses; in a group it propagates the flag to
    // every member's realism state (1:1 just sets the scalar).
    widget.chatService.setNsfwCooldownEnabled(value);
  }

  void _updateGroupTimeOfDay(String value) {
    rebuildState(() {
      _groupTimeOfDay = value;
    });
    _persistGroupTimeDay();
  }

  void _updateGroupDayCount(int value) {
    rebuildState(() {
      _groupDayCount = value;
    });
    _groupDayCountController.text = value.toString();
    _persistGroupTimeDay();
  }

  void _persistGroupTimeDay() {
    final group = widget.chatService.activeGroup;
    if (group == null) return;
    try {
      final map =
          group.defaultMemberRealismState.isNotEmpty &&
              group.defaultMemberRealismState != '{}'
          ? (jsonDecode(group.defaultMemberRealismState)
                    as Map<String, dynamic>?) ??
                {}
          : <String, dynamic>{};
      map['timeOfDay'] = _groupTimeOfDay;
      map['dayCount'] = _groupDayCount;
      if (_groupStoryStartDate != null) {
        map['storyStartDate'] = _groupStoryStartDate;
      } else {
        map.remove('storyStartDate');
      }
      if (_groupStoryStartTime != null) {
        map['storyStartTime'] = _groupStoryStartTime;
      } else {
        map.remove('storyStartTime');
      }
      group.defaultMemberRealismState = jsonEncode(map);
    } catch (_) {
      // Non-fatal
    }
  }

  void _resetAllRealismStates() {
    final cs = widget.chatService;
    if (cs.activeGroup == null) return;

    for (final c in cs.groupCharacters) {
      cs.resetRealismForGroupCharacter(c);
    }
  }

  void _resetCharacterRealism(CharacterCard character) {
    widget.chatService.resetRealismForGroupCharacter(character);
  }

  // Helper for chaos pressure color (matches _ChaosModeSection in chat_page)
  Color _pressureColorFor(int pressure) {
    final t = (pressure / 100).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF2EC4B6), const Color(0xFFE63946), t)!;
  }
}
