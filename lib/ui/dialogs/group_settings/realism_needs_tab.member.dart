// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'realism_needs_tab.dart';

extension _GroupRealismNeedsMemberCard on _GroupRealismNeedsTabState {
  /// One member's realism card (verbatim from the old inline map closure).
  Widget _buildMemberRealismCard(
    MapEntry<int, CharacterCard> entry,
    ChatService cs,
    GroupChat group,
    bool isRealismActive,
  ) {
    final index = entry.key;
    final char = entry.value;
    final liveState = isRealismActive
        ? cs.getRealismStateForGroupCharacter(char)
        : null;
    final emo = liveState?['emotion'] as String?;
    final bond = isRealismActive ? cs.getAffectionForGroupCharacter(char) : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          // Avatar (matches Prompt tab style)
          CircleAvatar(
            radius: 16,
            backgroundColor: groupCharAccentColor(index),
            backgroundImage: char.imagePath != null
                ? FileImage(File(char.imagePath!))
                : null,
            child: char.imagePath == null
                ? Text(
                    char.name.isNotEmpty ? char.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  char.name,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isRealismActive
                      ? (emo != null
                            ? 'Emotion: $emo • Bond: $bond'
                            : 'No realism data yet (will seed on next turn)')
                      : 'Realism inactive (Director Mode or master off)',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary(context),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // ── Editable Realism Baselines ─────────────────────
                const SizedBox(height: 8),
                // Relationship
                Row(
                  children: [
                    Icon(
                      Icons.favorite,
                      size: 14,
                      color: AppColors.resolve(
                        context,
                        Colors.pinkAccent,
                        Colors.pinkAccent,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Relationship',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    children: [
                      _sliderRow(
                        'Short-Term Bond',
                        _editShortTermBond[_getCharId(char)] ?? 50,
                        -300,
                        300,
                        char.name,
                        (v) => _updateEditShortTermBond(char, v.round()),
                      ),
                      _sliderRow(
                        'Long-Term Bond',
                        _editLongTermBond[_getCharId(char)] ?? 50,
                        -300,
                        300,
                        char.name,
                        (v) => _updateEditLongTermBond(char, v.round()),
                      ),
                      _sliderRow(
                        'Trust Level',
                        _editTrustLevel[_getCharId(char)] ?? 50,
                        -100,
                        100,
                        char.name,
                        (v) => _updateEditTrustLevel(char, v.round()),
                      ),
                    ],
                  ),
                ),
                // Starting Emotion
                Row(
                  children: [
                    Icon(
                      Icons.mood,
                      size: 14,
                      color: AppColors.resolve(
                        context,
                        Colors.amber,
                        Colors.amber,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Starting Emotion',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _emotionControllers[_getCharId(char)] ??=
                              TextEditingController(
                                text:
                                    _editEmotion[_getCharId(char)] ?? 'neutral',
                              ),
                          decoration: InputDecoration(
                            hintText: 'emotion',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: const TextStyle(fontSize: 11),
                          onChanged: (v) => _updateEditEmotion(char, v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue:
                              _editEmotionIntensity[_getCharId(char)] ??
                              'moderate',
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textPrimary(context),
                          ),
                          items: emotionIntensities
                              .map(
                                (e) =>
                                    DropdownMenuItem(value: e, child: Text(e)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              _updateEditEmotionIntensity(char, v);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                // ── End Editable Realism Baselines ──────────────────
                // Per-member Director/Verifier settings (new in Realism & Needs tab for groups).
                // These were previously only configurable at group creation time.
                // Now editable here for existing groups. Uses same perChar persistence + card ext patch.
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Director/Verifier',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary(context),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: Checkbox(
                        value: _verificationEnabled[_getCharId(char)] ?? false,
                        onChanged: (v) {
                          if (v != null) {
                            _updateMemberVerificationEnabled(char, v);
                          }
                        },
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                // Compact sliders + authority toggle for the Director settings.
                // Only shown when Director/Verifier is enabled for this member.
                if (_verificationEnabled[_getCharId(char)] ?? false) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'Max: ${_verificationMaxReprocesses[_getCharId(char)] ?? 1}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 80,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 8,
                            ),
                          ),
                          child: Slider(
                            value:
                                (_verificationMaxReprocesses[_getCharId(
                                          char,
                                        )] ??
                                        1)
                                    .toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            onChanged: (d) {
                              _updateMemberVerificationMaxReprocesses(
                                char,
                                d.round(),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Strict: ${_verificationStrictness[_getCharId(char)] ?? 3}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        width: 80,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 4,
                            ),
                          ),
                          child: Slider(
                            value:
                                (_verificationStrictness[_getCharId(char)] ?? 3)
                                    .toDouble(),
                            min: 1,
                            max: 5,
                            divisions: 4,
                            onChanged: (d) {
                              _updateMemberVerificationStrictness(
                                char,
                                d.round(),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Director authority (needs)',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 18,
                        width: 18,
                        child: Checkbox(
                          value:
                              _needsDirectorAuthority[_getCharId(char)] ??
                              false,
                          onChanged: (v) {
                            if (v != null) {
                              _updateMemberNeedsDirectorAuthority(char, v);
                            }
                          },
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => _resetCharacterRealism(char),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Reset',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.porchAmberOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
