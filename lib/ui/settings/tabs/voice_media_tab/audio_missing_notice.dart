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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Self-hiding: a warning line under Text-to-Speech only where
/// [AudioPlayback] says this machine cannot play sound (Linux without the
/// GStreamer base plugins), naming the package to install.
class AudioMissingNotice extends StatefulWidget {
  const AudioMissingNotice({super.key});

  @override
  State<AudioMissingNotice> createState() => _AudioMissingNoticeState();
}

class _AudioMissingNoticeState extends State<AudioMissingNotice> {
  final Future<bool> _available = AudioPlayback.available();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _available,
      builder: (context, snapshot) {
        if (snapshot.data != false) return const SizedBox.shrink();
        final ink = StatusColors.warningOf(context);
        return Container(
          key: const ValueKey('audio-missing-notice'),
          width: double.infinity,
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: StatusColors.warningPanelOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.volume_off_rounded, size: 16, color: ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AudioPlayback.missingMessage,
                  style: TextStyle(color: ink, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
