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
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';

/// Does the app's own KoboldCpp run for chat or the helper model? Advanced
/// Launch Options only reach that engine.
bool launchOptionsApply(StorageService storage) =>
    storage.backendSettings.backendType == 'kobold' ||
    storage.workerBackendType == 'kobold';

/// The note shown under Advanced Launch Options in place of Start/Restart.
String launchOptionsNoticeText(StorageService storage) {
  if (launchOptionsApply(storage)) {
    return 'No model loaded yet. Select a model on the Backend tab first.';
  }
  final b = storage.backendSettings;
  final kind = resolveRemoteProviderKind(
    backendType: b.backendType,
    url: b.remoteApiUrl,
  );
  final using = kind == RemoteProviderKind.custom
      ? 'your own AI server'
      : remoteProviderKindLabel(kind);
  return 'These options are for the built-in KoboldCpp engine. You\'re '
      'using $using, so they don\'t apply.';
}

/// Amber info box under Advanced Launch Options.
class LaunchOptionsNotice extends StatelessWidget {
  const LaunchOptionsNotice({
    super.key,
    required this.text,
    required this.accent,
  });

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: accent, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 11, color: accent)),
          ),
        ],
      ),
    );
  }
}
