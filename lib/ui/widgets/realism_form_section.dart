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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared Realism Engine configuration form.
///
/// Used by both the Manual Character Creator and AI Character Creator
/// to configure initial Realism Engine state for a character card.
class RealismFormSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final String timeOfDay;
  final ValueChanged<String> onTimeOfDayChanged;
  final int dayCount;
  final ValueChanged<int> onDayCountChanged;
  final int shortTermBond;
  final ValueChanged<int> onShortTermBondChanged;
  final int longTermBond;
  final ValueChanged<int> onLongTermBondChanged;
  final int trustLevel;
  final ValueChanged<int> onTrustLevelChanged;
  final String emotion;
  final ValueChanged<String> onEmotionChanged;
  final String emotionIntensity;
  final ValueChanged<String> onEmotionIntensityChanged;
  final bool nsfwCooldownEnabled;
  final ValueChanged<bool> onNsfwCooldownChanged;
  final bool chaosModeEnabled;
  final ValueChanged<bool> onChaosModeChanged;
  final String currentTask;
  final ValueChanged<String> onCurrentTaskChanged;

  const RealismFormSection({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.timeOfDay,
    required this.onTimeOfDayChanged,
    required this.dayCount,
    required this.onDayCountChanged,
    required this.shortTermBond,
    required this.onShortTermBondChanged,
    required this.longTermBond,
    required this.onLongTermBondChanged,
    required this.trustLevel,
    required this.onTrustLevelChanged,
    required this.emotion,
    required this.onEmotionChanged,
    required this.emotionIntensity,
    required this.onEmotionIntensityChanged,
    required this.nsfwCooldownEnabled,
    required this.onNsfwCooldownChanged,
    required this.chaosModeEnabled,
    required this.onChaosModeChanged,
    required this.currentTask,
    required this.onCurrentTaskChanged,
  });

  static const _timeOptions = [
    'dawn',
    'morning',
    'late_morning',
    'afternoon',
    'evening',
    'night',
  ];

  static const _intensityOptions = ['mild', 'moderate', 'strong'];

  String _formatTimeLabel(String value) {
    return value
        .split('_')
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  String _shortTermTierName(int score) {
    if (score >= 80) return 'Devoted';
    if (score >= 50) return 'Affectionate';
    if (score >= 20) return 'Warm';
    if (score >= 5) return 'Friendly';
    if (score >= -4) return 'Neutral';
    if (score >= -19) return 'Cool';
    if (score >= -49) return 'Distant';
    if (score >= -79) return 'Hostile';
    return 'Despised';
  }

  String _longTermTierName(int score) {
    if (score >= 80) return 'Soulbound';
    if (score >= 50) return 'Deep Bond';
    if (score >= 20) return 'Close';
    if (score >= 5) return 'Familiar';
    if (score >= -4) return 'Acquaintance';
    if (score >= -19) return 'Uneasy';
    if (score >= -49) return 'Estranged';
    if (score >= -79) return 'Broken';
    return 'Nemesis';
  }

  String _trustLevelName(int level) {
    if (level >= 80) return 'Absolute Trust';
    if (level >= 50) return 'Deep Trust';
    if (level >= 20) return 'Trusting';
    if (level >= 5) return 'Cautious Trust';
    if (level >= -4) return 'Neutral';
    if (level >= -19) return 'Wary';
    if (level >= -49) return 'Suspicious';
    if (level >= -79) return 'Paranoid';
    return 'Absolute Distrust';
  }

  Color _bondColor(int score) {
    if (score >= 20) return Colors.greenAccent;
    if (score >= 0) return Colors.blueAccent;
    if (score >= -19) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  Color _trustColor(int level) {
    if (level >= 20) return Colors.tealAccent;
    if (level >= 0) return Colors.blueAccent;
    if (level >= -19) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Master Toggle ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: enabled ? Colors.blueAccent.withValues(alpha: 0.4) : Colors.white12,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: enabled
                      ? Colors.blueAccent.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.psychology,
                  color: enabled ? Colors.blueAccent : Colors.white38,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enable Realism Engine',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      enabled
                          ? 'Character will start with pre-configured state'
                          : 'Realism Engine will use default values',
                      style: TextStyle(
                        color: enabled ? Colors.blueAccent : Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: enabled,
                onChanged: onEnabledChanged,
                activeTrackColor: Colors.blueAccent.withValues(alpha: 0.5),
                activeThumbColor: Colors.blueAccent,
              ),
            ],
          ),
        ),

        // ── Configuration Form (only when enabled) ──
        if (enabled) ...[
          const SizedBox(height: 20),

          // Time & Day Section
          _sectionHeader(Icons.schedule, 'Time & Day', Colors.amberAccent),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                // Time of Day dropdown
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Time of Day', style: _labelStyle),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButton<String>(
                          value: timeOfDay,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          underline: const SizedBox(),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: _timeOptions.map((t) => DropdownMenuItem(
                            value: t,
                            child: Text(_formatTimeLabel(t)),
                          )).toList(),
                          onChanged: (v) { if (v != null) onTimeOfDayChanged(v); },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Day Number
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Day Number', style: _labelStyle),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          controller: TextEditingController(text: dayCount.toString())
                            ..selection = TextSelection.fromPosition(
                              TextPosition(offset: dayCount.toString().length),
                            ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            if (n != null && n >= 1) onDayCountChanged(n);
                          },
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Relationship Section
          _sectionHeader(Icons.favorite, 'Relationship', Colors.pinkAccent),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              children: [
                // Short-Term Bond
                _sliderRow(
                  label: 'Short-Term Bond',
                  value: shortTermBond,
                  min: -300,
                  max: 300,
                  tierName: _shortTermTierName(shortTermBond),
                  color: _bondColor(shortTermBond),
                  onChanged: (v) => onShortTermBondChanged(v.round()),
                ),
                const SizedBox(height: 16),
                // Long-Term Bond
                _sliderRow(
                  label: 'Long-Term Bond',
                  value: longTermBond,
                  min: -300,
                  max: 300,
                  tierName: _longTermTierName(longTermBond),
                  color: _bondColor(longTermBond),
                  onChanged: (v) => onLongTermBondChanged(v.round()),
                ),
                const SizedBox(height: 16),
                // Trust Level
                _sliderRow(
                  label: 'Trust Level',
                  value: trustLevel,
                  min: -100,
                  max: 100,
                  tierName: _trustLevelName(trustLevel),
                  color: _trustColor(trustLevel),
                  onChanged: (v) => onTrustLevelChanged(v.round()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Emotion Section
          _sectionHeader(Icons.mood, 'Starting Emotion', Colors.purpleAccent),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Row(
              children: [
                // Emotion text field
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Emotion', style: _labelStyle),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          controller: TextEditingController(text: emotion)
                            ..selection = TextSelection.fromPosition(
                              TextPosition(offset: emotion.length),
                            ),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          onChanged: onEmotionChanged,
                          decoration: InputDecoration(
                            hintText: 'e.g. curious, guarded, amused',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Intensity selector
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Intensity', style: _labelStyle),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButton<String>(
                          value: emotionIntensity,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E293B),
                          underline: const SizedBox(),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          items: _intensityOptions.map((i) => DropdownMenuItem(
                            value: i,
                            child: Text(i[0].toUpperCase() + i.substring(1)),
                          )).toList(),
                          onChanged: (v) { if (v != null) onEmotionIntensityChanged(v); },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Optional Toggles
          _sectionHeader(Icons.tune, 'Optional Features', Colors.tealAccent),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              children: [
                _toggleRow(
                  icon: Icons.thermostat,
                  label: 'NSFW Cooldown System',
                  subtitle: 'Realistic arousal/refractory mechanics',
                  value: nsfwCooldownEnabled,
                  onChanged: onNsfwCooldownChanged,
                ),
                const Divider(color: Colors.white10, height: 24),
                _toggleRow(
                  icon: Icons.casino,
                  label: 'Chaos Mode (Chance Time)',
                  subtitle: 'Random narrative events during roleplay',
                  value: chaosModeEnabled,
                  onChanged: onChaosModeChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Task / Quest Section
          _sectionHeader(Icons.flag, 'Current Task / Quest', Colors.orangeAccent),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Task', style: _labelStyle),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: TextEditingController(text: currentTask)
                      ..selection = TextSelection.fromPosition(
                        TextPosition(offset: currentTask.length),
                      ),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 3,
                    minLines: 1,
                    onChanged: onCurrentTaskChanged,
                    decoration: InputDecoration(
                      hintText: 'e.g. Find the missing artifact, Survive the first day at school',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Sets the initial quest or objective when a new conversation starts.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  static BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    );
  }

  static const _labelStyle = TextStyle(
    color: Colors.white70,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  Widget _sliderRow({
    required String label,
    required int value,
    required int min,
    required int max,
    required String tierName,
    required Color color,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: _labelStyle),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$tierName ($value)',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            inactiveTrackColor: Colors.white12,
            thumbColor: color,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, color: value ? Colors.tealAccent : Colors.white38, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                color: value ? Colors.white : Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              )),
              Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: Colors.tealAccent.withValues(alpha: 0.5),
          activeThumbColor: Colors.tealAccent,
        ),
      ],
    );
  }
}
