// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'needs_tab.dart';

extension _GroupNeedsMemberCard on _GroupNeedsTabState {
  /// One member's needs card (verbatim from the old inline map closure).
  Widget _buildMemberNeedsCard(MapEntry<int, CharacterCard> entry) {
    final index = entry.key;
    final char = entry.value;
    final id = _getCharId(char);
    final baselines = _needsBaselines[id] ?? {};

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar + name + reset
          Row(
            children: [
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
                child: Text(
                  char.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => _resetCharacterNeeds(char),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Reset',
                  style: TextStyle(fontSize: 12, color: Colors.tealAccent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _needsSlider(
            'Hunger',
            baselines[_kHunger] ?? 80,
            (v) => _updateNeedsBaseline(id, _kHunger, v),
          ),
          _needsSlider(
            'Bladder',
            baselines[_kBladder] ?? 80,
            (v) => _updateNeedsBaseline(id, _kBladder, v),
          ),
          _needsSlider(
            'Energy',
            baselines[_kEnergy] ?? 80,
            (v) => _updateNeedsBaseline(id, _kEnergy, v),
          ),
          _needsSlider(
            'Social',
            baselines[_kSocial] ?? 80,
            (v) => _updateNeedsBaseline(id, _kSocial, v),
          ),
          _needsSlider(
            'Fun',
            baselines[_kFun] ?? 80,
            (v) => _updateNeedsBaseline(id, _kFun, v),
          ),
          _needsSlider(
            'Hygiene',
            baselines[_kHygiene] ?? 80,
            (v) => _updateNeedsBaseline(id, _kHygiene, v),
          ),
          _needsSlider(
            'Comfort',
            baselines[_kComfort] ?? 80,
            (v) => _updateNeedsBaseline(id, _kComfort, v),
          ),

          const SizedBox(height: 8),
          Divider(color: AppColors.borderOf(context), height: 1),
          const SizedBox(height: 8),

          // Enjoys low hygiene
          Row(
            children: [
              Icon(
                Icons.water_drop_outlined,
                size: 14,
                color: Colors.tealAccent,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Enjoys low hygiene',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ),
              SizedBox(
                height: 20,
                width: 20,
                child: Checkbox(
                  value: _enjoysLowHygiene[id] ?? false,
                  onChanged: (v) {
                    if (v != null) {
                      _updateMemberEnjoysLowHygiene(char, v);
                    }
                  },
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _needsSlider(String label, int value, ValueChanged<int> onChanged) {
    final baseline = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Colors.tealAccent,
            inactiveTrackColor: AppColors.borderOf(context),
            thumbColor: Colors.tealAccent,
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
      ],
    );

    return baseline;
  }
}
