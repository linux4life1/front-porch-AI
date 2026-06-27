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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

class RealismSection extends StatefulWidget {
  final ChatService chatService;
  const RealismSection({super.key, required this.chatService});

  @override
  State<RealismSection> createState() => RealismSectionState();
}

class RealismSectionState extends State<RealismSection> {
  bool _expanded = true; // default expanded

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chat, _) {
        final enabled = chat.realismEnabled;
        final storageService = Provider.of<StorageService>(context);

        // Bond colors per tier — made light-mode safe
        Color getTierColor(int tier) {
          // Strong positive tiers (vibrant, work on both themes)
          if (tier >= 10) return Colors.deepPurpleAccent;
          if (tier >= 9) return Colors.purpleAccent;
          if (tier >= 8) return Colors.pinkAccent;
          if (tier >= 7) return Colors.pink;
          if (tier >= 6) return Colors.pink.shade200;
          if (tier >= 5) return Colors.orangeAccent;
          if (tier >= 4) return Colors.greenAccent;

          // Neutral / low tiers — use context-aware versions for light mode readability
          if (tier >= 3) {
            return AppColors.resolve(
              context,
              Colors.lightBlue,
              Colors.blue.shade700,
            );
          }
          if (tier >= 2) {
            return AppColors.resolve(
              context,
              Colors.blueGrey,
              Colors.blueGrey.shade700,
            );
          }
          if (tier >= 1) {
            return AppColors.resolve(
              context,
              Colors.grey.shade400,
              Colors.grey.shade700,
            );
          }
          if (tier == 0) {
            return AppColors.textTertiary(context);
          }

          // Negative tiers (mostly dark reds/browns in dark mode — they become readable darks on light)
          if (tier >= -1) {
            return AppColors.resolve(
              context,
              Colors.orangeAccent.shade100,
              Colors.orange.shade700,
            );
          }
          if (tier >= -2) {
            return AppColors.resolve(
              context,
              Colors.redAccent.shade100,
              Colors.red.shade600,
            );
          }
          if (tier >= -3) return Colors.redAccent;
          if (tier >= -4) return Colors.red;
          if (tier >= -5) {
            return AppColors.resolve(
              context,
              Colors.red.shade900,
              Colors.red.shade800,
            );
          }
          if (tier >= -6) {
            return AppColors.resolve(
              context,
              Colors.brown.shade900,
              Colors.brown.shade700,
            );
          }
          if (tier >= -7) {
            return AppColors.resolve(
              context,
              Colors.deepOrange.shade900,
              Colors.deepOrange.shade700,
            );
          }
          if (tier >= -8) {
            return AppColors.resolve(
              context,
              Colors.amber.shade900,
              Colors.amber.shade800,
            );
          }
          if (tier >= -9) {
            return AppColors.resolve(
              context,
              Colors.orange.shade900,
              Colors.orange.shade800,
            );
          }
          return AppColors.textPrimary(context);
        }

        final shortTermColor = getTierColor(
          chat.relationshipService.relationshipTier,
        );
        final longTermColor = getTierColor(
          chat.relationshipService.longTermTier,
        );

        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Collapsible Header ──
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _expanded ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.theater_comedy,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Realism Mode',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: enabled,
                          activeThumbColor: AppColors.resolve(
                            context,
                            Colors.tealAccent,
                            Colors.teal.shade700,
                          ),
                          onChanged: chat.isGenerating
                              ? null
                              : (val) {
                                  chat.setRealismEnabled(val);
                                  if (val) setState(() => _expanded = true);
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Expanded Content ──
              if (enabled && _expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(
                        color: AppColors.borderOf(
                          context,
                        ).withValues(alpha: 0.2),
                        height: 1,
                      ),
                      const SizedBox(height: 10),

                      // ── Short-Term Tension ──
                      Tooltip(
                        message:
                            'Short-term Dynamic: The immediate "tension in the room" or how they feel about you right now. Evolves quickly based on recent events.',
                        child: Row(
                          children: [
                            Icon(
                              chat.relationshipService.relationshipTier < 0
                                  ? Icons.heart_broken
                                  : Icons.favorite,
                              size: 13,
                              color: shortTermColor,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Short-Term Bond: ${chat.relationshipService.shortTermTierName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: shortTermColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${chat.relationshipService.affectionScore.abs()}/${chat.relationshipService.shortTermProgressTarget}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value:
                              chat.relationshipService.shortTermProgressPercent,
                          minHeight: 5,
                          backgroundColor: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            shortTermColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Long-Term Bond ──
                      Tooltip(
                        message:
                            'Long-term Relationship: Your deep, overarching history together. Evolves slowly and sets the foundation for your interactions.',
                        child: Row(
                          children: [
                            Icon(
                              chat.relationshipService.longTermTier < 0
                                  ? Icons.heart_broken_sharp
                                  : Icons.monitor_heart,
                              size: 13,
                              color: longTermColor,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Long-Term Bond: ${chat.relationshipService.longTermTierName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: longTermColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${chat.relationshipService.longTermScore.abs()}/${chat.relationshipService.longTermProgressTarget}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value:
                              chat.relationshipService.longTermProgressPercent,
                          minHeight: 5,
                          backgroundColor: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            longTermColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Trust / Distrust ──
                      Tooltip(
                        message:
                            'Trust: Paranoia vs absolute faith. Dictates whether the character questions your motives or readily believes you.',
                        child: Row(
                          children: [
                            Icon(
                              chat.relationshipService.trustLevel < 0
                                  ? Icons.vpn_key_off
                                  : Icons.vpn_key,
                              size: 13,
                              color: chat.relationshipService.trustLevel < 0
                                  ? Colors.redAccent
                                  : Colors.amber,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                'Trust: ${chat.relationshipService.trustTierName}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: chat.relationshipService.trustLevel < 0
                                      ? Colors.redAccent
                                      : Colors.amber,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${chat.relationshipService.trustLevel.abs()}/${chat.relationshipService.trustProgressTarget}',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: chat.relationshipService.trustProgressPercent,
                          minHeight: 5,
                          backgroundColor: AppColors.borderOf(
                            context,
                          ).withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.resolve(
                              context,
                              const Color(
                                0xFFEF5350,
                              ), // negative trust (red accent; custom state, no dedicated AppColors light variant)
                              const Color(0xFFFFB300), // positive/amber
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Emotion ──
                      if (chat.characterEmotion.isNotEmpty) ...[
                        Row(
                          children: [
                            Text(
                              _emotionEmoji(chat.characterEmotion),
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${chat.characterEmotion.substring(0, 1).toUpperCase()}${chat.characterEmotion.substring(1)} (${chat.emotionIntensity})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── Time of Day ──
                      Row(
                        children: [
                          Text(
                            _timeEmoji(chat.timeService.timeOfDay),
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _timeLabel(chat.timeService.timeOfDay),
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          const Spacer(),
                          // Manual time nudge: back
                          if (chat.realismEnabled)
                            GestureDetector(
                              onTap: () => chat.nudgeTimePeriod(-1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Icon(
                                  Icons.chevron_left,
                                  size: 16,
                                  color: AppColors.iconSecondary(context),
                                ),
                              ),
                            ),
                          Text(
                            '${chat.timeService.narrativeWeekday.substring(0, 3)} · Day ${chat.timeService.dayCount}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary(context),
                            ),
                          ),
                          // Manual time nudge: forward
                          if (chat.realismEnabled)
                            GestureDetector(
                              onTap: () => chat.nudgeTimePeriod(1),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: AppColors.iconSecondary(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Time period dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final period in [
                            'dawn',
                            'morning',
                            'late_morning',
                            'afternoon',
                            'evening',
                            'night',
                          ])
                            Column(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: chat.timeService.timeOfDay == period
                                        ? AppColors.resolve(
                                            context,
                                            Colors.amber,
                                            Colors.amber.shade700,
                                          )
                                        : AppColors.borderOf(
                                            context,
                                          ).withValues(alpha: 0.25),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _timeDotLabel(period),
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: chat.timeService.timeOfDay == period
                                        ? AppColors.resolve(
                                            context,
                                            Colors.amber,
                                            Colors.amber.shade800,
                                          )
                                        : AppColors.textTertiary(context),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      // OOC time-skip toast removed — skip info now appears
                      // in the delta row on the next AI message bubble.
                      const SizedBox(height: 12),

                      // ── Automatic Passage of Time Toggle ──
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Automatic Passage of Time',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: chat.timeService.passageOfTimeEnabled,
                              activeThumbColor: AppColors.resolve(
                                context,
                                Colors.blueAccent,
                                Colors.blue.shade700,
                              ),
                              onChanged: chat.isGenerating
                                  ? null
                                  : (val) => chat.timeService
                                        .setPassageOfTimeEnabled(val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Time advances automatically as you chat. Manual controls remain available.',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Needs Simulation Toggle + Bars ──
                      Row(
                        children: [
                          Icon(
                            Icons.battery_std,
                            size: 14,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              'Needs Simulation',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary(context),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            child: Switch(
                              value: chat.needsSimEnabled,
                              activeThumbColor: AppColors.resolve(
                                context,
                                Colors.tealAccent,
                                Colors.teal.shade700,
                              ),
                              onChanged: chat.isGenerating
                                  ? null
                                  : (val) => chat.setNeedsSimEnabled(val),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tracks satisfaction levels (hunger, bladder, energy, social, fun, hygiene, comfort). Higher = more sated / less urgent (100 = full, 0 = critical). Affects prompts & behavior when low.',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 10,
                        ),
                      ),
                      if (chat.needsSimEnabled &&
                          chat.needsSimulation.vector.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        for (final entry in chat.needsSimulation.vector.entries)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 58,
                                  child: Text(
                                    entry.key[0].toUpperCase() +
                                        entry.key.substring(1),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: (entry.value / 100.0).clamp(
                                        0.0,
                                        1.0,
                                      ),
                                      minHeight: 4,
                                      backgroundColor: AppColors.borderOf(
                                        context,
                                      ).withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        entry.value <=
                                                ChatService
                                                    .needCriticalThreshold
                                            ? Colors.redAccent
                                            : AppColors.resolve(
                                                context,
                                                Colors.tealAccent,
                                                Colors.teal.shade700,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${entry.value}',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: AppColors.textTertiary(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),

                      // ── NSFW Enhancements Submenu ──
                      NsfwEnhancementsSection(chat: chat),

                      const SizedBox(height: 12),
                      Divider(
                        color: AppColors.borderOf(
                          context,
                        ).withValues(alpha: 0.2),
                        height: 1,
                      ),
                      const SizedBox(height: 10),

                      // ── Realism Performance ──
                      Row(
                        children: [
                          Icon(
                            Icons.speed,
                            size: 14,
                            color: AppColors.resolve(
                              context,
                              Colors.tealAccent,
                              Colors.teal.shade700,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: RichText(
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'One-Shot Eval ',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.resolve(
                                        context,
                                        Colors.tealAccent,
                                        Colors.teal.shade700,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: '(Experimental)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 20,
                            child: Switch(
                              value: storageService.realismOneShotEval,
                              activeThumbColor: AppColors.resolve(
                                context,
                                Colors.tealAccent,
                                Colors.teal.shade700,
                              ),
                              onChanged: chat.isGenerating
                                  ? null
                                  : (val) {
                                      storageService.setRealismOneShotEval(val);
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fuses relationship + scene evals into a single LLM call to double the processing speed. May be less accurate on < 8B param models.',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _emotionEmoji(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'amused':
      case 'playful':
      case 'happy':
        return '😄';
      case 'angry':
      case 'furious':
        return '😠';
      case 'sad':
      case 'melancholy':
        return '😢';
      case 'anxious':
      case 'nervous':
      case 'worried':
        return '😰';
      case 'excited':
      case 'thrilled':
        return '🤩';
      case 'flirtatious':
      case 'aroused':
        return '😏';
      case 'calm':
      case 'relaxed':
      case 'content':
        return '😌';
      case 'suspicious':
      case 'wary':
        return '🤨';
      case 'fearful':
      case 'scared':
        return '😨';
      case 'embarrassed':
      case 'flustered':
        return '😳';
      case 'annoyed':
      case 'irritated':
        return '😤';
      case 'confused':
      case 'conflicted':
        return '😕';
      case 'protective':
        return '🛡️';
      default:
        return '🎭';
    }
  }

  String _timeEmoji(String time) {
    switch (time) {
      case 'dawn':
        return '🌅';
      case 'morning':
        return '☀️';
      case 'late_morning':
        return '🌤️';
      case 'afternoon':
        return '☀️';
      case 'evening':
        return '🌇';
      case 'night':
        return '🌙';
      default:
        return '🕐';
    }
  }

  String _timeLabel(String time) {
    switch (time) {
      case 'dawn':
        return 'Dawn';
      case 'morning':
        return 'Morning';
      case 'late_morning':
        return 'Late Morning';
      case 'afternoon':
        return 'Afternoon';
      case 'evening':
        return 'Evening';
      case 'night':
        return 'Night';
      default:
        return time;
    }
  }

  String _timeDotLabel(String period) {
    switch (period) {
      case 'dawn':
        return 'D';
      case 'morning':
        return 'M';
      case 'late_morning':
        return 'LM';
      case 'afternoon':
        return 'A';
      case 'evening':
        return 'E';
      case 'night':
        return 'N';
      default:
        return '';
    }
  }
}

