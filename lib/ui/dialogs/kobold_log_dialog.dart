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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/log_view.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';

/// Dialog that displays live KoboldCPP process logs in real-time.
/// Matches the visual style of [ContextViewerDialog].
class KoboldLogDialog extends StatefulWidget {
  const KoboldLogDialog({super.key});

  @override
  State<KoboldLogDialog> createState() => _KoboldLogDialogState();
}

class _KoboldLogDialogState extends State<KoboldLogDialog> {
  @override
  Widget build(BuildContext context) {
    return Consumer2<LLMProvider, KoboldService>(
      builder: (context, llmProvider, kobold, _) {
        final logs = kobold.logs;
        final isRunning = kobold.isRunning;
        final isReady = kobold.isReady;

        final statusColor = isRunning ? Colors.greenAccent : Colors.white38;
        final statusLabel = isRunning
            ? (isReady ? 'Ready' : 'Starting…')
            : 'Stopped';

        return Dialog(
          backgroundColor: AppColors.backgroundOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 720,
              maxHeight: 620,
              minWidth: 480,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.terminal,
                        color: Colors.greenAccent,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'KoboldCpp Log',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Tooltip(
                        message: 'Copy all logs',
                        child: IconButton(
                          icon: const Icon(
                            Icons.copy_all,
                            color: Colors.white38,
                            size: 18,
                          ),
                          onPressed: logs.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(
                                    ClipboardData(text: logs.join('\n')),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Logs copied to clipboard'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: Colors.white54,
                          size: 20,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                if (logs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${logs.length} line${logs.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Colors.white24,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '· Text is selectable and copyable',
                          style: TextStyle(color: Colors.white12, fontSize: 11),
                        ),
                      ],
                    ),
                  ),

                Flexible(
                  child: logs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.terminal,
                                color: Colors.white12,
                                size: 36,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'No log output yet.',
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Start the backend from Settings → Backend, or from the Model Settings dialog.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white24,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: LogView(logs: logs),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
