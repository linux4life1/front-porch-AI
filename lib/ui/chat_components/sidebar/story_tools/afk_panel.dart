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
import '../sidebar_tokens.dart';

/// Dynamic Responses (AFK) panel — enable switch + a compact gear flyout
/// (mirrors the Journal recap's settings gear) holding the two knobs: how
/// often an idle auto-response fires and how many fire before it stops.
///
/// All three values live in the shared persisted generation settings
/// (`dynamicResponses`, `dynamicResponseInterval`, `dynamicResponseMaxMessages`)
/// so this panel, the `/afk` command, and the web settings stay in lockstep —
/// no parallel AFK state. Enabling/disabling routes through the ChatService's
/// existing resume/pause so the idle timer arms immediately when appropriate.
class AfkPanel extends StatefulWidget {
  final ChatService chat;
  const AfkPanel({super.key, required this.chat});

  @override
  State<AfkPanel> createState() => _AfkPanelState();
}

class _AfkPanelState extends State<AfkPanel> {
  bool _showSettings = false;
  double? _dragInterval; // live value while dragging (before persist)
  double? _dragMessages;

  String _fmtInterval(int seconds) =>
      seconds % 60 == 0 ? '${seconds ~/ 60} min' : '${seconds}s';

  @override
  Widget build(BuildContext context) {
    final storage = Provider.of<StorageService>(context);
    final accent = AppColors.porchHoneyOf(context);
    final enabled = storage.dynamicResponses;
    final interval = storage.dynamicResponseInterval;
    final maxMessages = storage.dynamicResponseMaxMessages;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SidebarSubHeader(
          icon: Icons.bedtime_outlined,
          label: 'Dynamic Responses (AFK)',
          accent: accent,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Settings gear (mirrors the Journal recap gear)
              InkWell(
                onTap: () => setState(() => _showSettings = !_showSettings),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Icon(
                    Icons.tune,
                    size: 14,
                    color: _showSettings
                        ? accent
                        : AppColors.iconSecondary(context),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Switch(
                value: enabled,
                onChanged: (v) {
                  storage.setDynamicResponses(v);
                  // Reuse the existing lifecycle so the idle timer arms/cancels
                  // right away rather than waiting for the next page entry.
                  if (v) {
                    widget.chat.resumeDynamicResponses();
                  } else {
                    widget.chat.pauseDynamicResponses();
                  }
                  setState(() {});
                },
                activeThumbColor: accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        // Collapsed summary when on (so the values are visible without opening
        // the gear); hidden while the settings flyout is showing them anyway.
        if (enabled && !_showSettings) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Text(
              'Up to $maxMessages ${maxMessages == 1 ? 'scene' : 'scenes'} · '
              'one every ${_fmtInterval(interval)}',
              style: TextStyle(
                fontSize: 10,
                color: AppColors.textTertiary(context),
              ),
            ),
          ),
        ],
        // Gear flyout: the two AFK knobs.
        if (_showSettings) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Reply interval
                  Row(
                    children: [
                      Text(
                        'Reply every',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _fmtInterval(
                          (_dragInterval ?? interval.toDouble()).round(),
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: _dragInterval ?? interval.toDouble(),
                      min: 30,
                      max: 300,
                      divisions: 27,
                      activeColor: accent,
                      inactiveColor: AppColors.borderOf(context),
                      onChanged: (val) =>
                          setState(() => _dragInterval = val),
                      onChangeEnd: (val) {
                        _dragInterval = null;
                        storage.setDynamicResponseInterval(val.toInt());
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Message count
                  Row(
                    children: [
                      Text(
                        'Messages before stopping',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${(_dragMessages ?? maxMessages.toDouble()).round()}',
                        style: TextStyle(
                          fontSize: 11,
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                      ),
                    ),
                    child: Slider(
                      value: _dragMessages ?? maxMessages.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      activeColor: accent,
                      inactiveColor: AppColors.borderOf(context),
                      onChanged: (val) =>
                          setState(() => _dragMessages = val),
                      onChangeEnd: (val) {
                        _dragMessages = null;
                        storage.setDynamicResponseMaxMessages(val.toInt());
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Away pace (Living Time): story time per snapshot —
                  // deterministic; the model never chooses the span.
                  Row(
                    children: [
                      Text(
                        'Story time per scene',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const Spacer(),
                      DropdownButton<int>(
                        value:
                            const [1, 3, 6].contains(
                              storage.dynamicResponsePacePeriods,
                            )
                            ? storage.dynamicResponsePacePeriods
                            : 1,
                        isDense: true,
                        dropdownColor: AppColors.cardOf(context),
                        style: TextStyle(fontSize: 11, color: accent),
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('a few hours'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text('half the day'),
                          ),
                          DropdownMenuItem(
                            value: 6,
                            child: Text('a full day'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            storage.setDynamicResponsePacePeriods(v);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'While you step away, the character keeps living their day '
                    '— a few short solitary scenes so the world feels alive. '
                    'Type anything to stop. Also available as /afk.',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textTertiary(context),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
