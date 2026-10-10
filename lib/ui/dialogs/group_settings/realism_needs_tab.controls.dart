// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'realism_needs_tab.dart';

extension _GroupRealismNeedsControls on _GroupRealismNeedsTabState {
  /// The Time & Day and Chaos Mode blocks of the global settings card
  /// (verbatim from the old inline build).
  List<Widget> _timeAndChaosControls(ChatService cs, GroupChat group) {
    return [
      const SizedBox(height: 14),
      Divider(color: AppColors.borderOf(context), height: 1),
      const SizedBox(height: 12),

      // Time & Day (group-wide)
      Row(
        children: [
          Icon(
            Icons.schedule,
            size: 18,
            color: AppColors.resolve(
              context,
              Colors.lightBlueAccent,
              Colors.lightBlueAccent,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Time & Day',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Sets the starting time and day for all characters in this group.',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _groupTimeOfDay,
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
              style: const TextStyle(fontSize: 12),
              items: ['morning', 'afternoon', 'evening', 'night']
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(e, style: const TextStyle(fontSize: 12)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) _updateGroupTimeOfDay(v);
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _groupDayCountController,
              decoration: InputDecoration(
                hintText: 'Day',
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
              style: const TextStyle(fontSize: 12),
              keyboardType: TextInputType.number,
              onChanged: (v) {
                final val = int.tryParse(v) ?? 1;
                _updateGroupDayCount(val);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      // Story Calendar seed for FRESH sessions (the live chat's
      // clock is set from the Story Calendar dialog instead).
      StoryBeginsRow(
        storyStartDate: _groupStoryStartDate,
        onStoryStartDateChanged: (v) {
          rebuildState(() => _groupStoryStartDate = v);
          _persistGroupTimeDay();
        },
        storyStartTime: _groupStoryStartTime,
        onStoryStartTimeChanged: (v) {
          rebuildState(() => _groupStoryStartTime = v);
          _persistGroupTimeDay();
        },
      ),

      const SizedBox(height: 14),
      Divider(color: AppColors.borderOf(context), height: 1),
      const SizedBox(height: 12),

      // Chaos Mode
      Row(
        children: [
          Text('🎰', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Chaos Mode (Chance Time)',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Switch(
            value: _chaosModeEnabled,
            activeThumbColor: const Color(0xFFFFD166),
            onChanged: _updateChaosMode,
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(
        'Injects random narrative events based on accumulating pressure. Great for surprising group dynamics.',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary(context)),
      ),

      if (_chaosModeEnabled) ...[
        const SizedBox(height: 10),

        // Pressure readout (live from service)
        Row(
          children: [
            Icon(
              Icons.casino_rounded,
              size: 14,
              color: _pressureColorFor(cs.chaosModeService.chaosPressure),
            ),
            const SizedBox(width: 6),
            Text(
              'Pressure: ${cs.chaosPressure}%',
              style: TextStyle(
                fontSize: 11,
                color: _pressureColorFor(cs.chaosModeService.chaosPressure),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // NSFW spicy toggle
        Row(
          children: [
            Text('🌶️', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Include spicy/NSFW events',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: Switch(
                value: _chaosNsfwEnabled,
                activeTrackColor: AppColors.porchAmberOf(context),
                onChanged: _updateChaosNsfw,
              ),
            ),
          ],
        ),
      ],
    ];
  }
}
