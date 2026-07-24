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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class RagSetupDialog extends StatefulWidget {
  const RagSetupDialog({super.key});

  @override
  State<RagSetupDialog> createState() => RagSetupDialogState();
}

class RagSetupDialogState extends State<RagSetupDialog> {
  bool _isSettingUp = false;
  bool _isDone = false;

  @override
  Widget build(BuildContext context) {
    final embeddings = Provider.of<EmbeddingService>(context);

    return Dialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _isSettingUp
              ? _buildSetupView(embeddings)
              : _buildConsentView(),
        ),
      ),
    );
  }

  Widget _buildConsentView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purpleAccent, Colors.deepPurple],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.psychology,
                color: AppColors.textPrimary(context),
                size: 22,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enable Memory (RAG)',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),

        // Explanation
        Text(
          'Memory (RAG) gives your AI the ability to recall past conversations — even ones that have left the context window.',
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 13,
            height: 1.5,
          ),
        ),
        SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.12),
            ),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(
                icon: Icons.download,
                color: AppColors.formMasterAccent,
                text: 'Downloads a ~550 MB AI embedding model on first setup',
              ),
              SizedBox(height: 8),
              InfoRow(
                icon: Icons.memory,
                color: Colors.tealAccent,
                text:
                    'Runs inside the app on your CPU — no data leaves your machine',
              ),
              SizedBox(height: 8),
              InfoRow(
                icon: Icons.search,
                color: Colors.purpleAccent,
                text:
                    'Searches past messages for relevant context to include in prompts',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _isSettingUp = true);
                _startSetup();
              },
              icon: Icon(Icons.rocket_launch, size: 16),
              label: Text('Set Up & Enable'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: AppColors.textPrimary(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSetupView(EmbeddingService embeddings) {
    final hasError = embeddings.setupError != null;
    final progress = embeddings.setupProgress;
    final showProgress = progress >= 0 && progress <= 1.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            if (_isDone)
              const Icon(
                Icons.check_circle,
                color: Colors.greenAccent,
                size: 28,
              )
            else if (hasError)
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 28)
            else
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.purpleAccent,
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _isDone
                    ? 'Setup Complete'
                    : hasError
                    ? 'Setup Failed'
                    : 'Setting Up Memory...',
                style: TextStyle(
                  color: _isDone
                      ? Colors.greenAccent
                      : hasError
                      ? Colors.redAccent
                      : AppColors.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),

        // Status message
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasError
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : AppColors.borderOf(context).withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                embeddings.setupStatus,
                style: TextStyle(
                  color: hasError
                      ? Colors.redAccent
                      : AppColors.textSecondary(context),
                  fontSize: 13,
                ),
              ),
              if (showProgress) ...[
                SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.borderOf(
                      context,
                    ).withValues(alpha: 0.12),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.purpleAccent,
                    ),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ],
              if (!showProgress && !hasError && !_isDone) ...[
                SizedBox(height: 10),
                ClipRRect(
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: AppColors.borderOf(
                      context,
                    ).withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.purpleAccent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (hasError && embeddings.setupError != null) ...[
          const SizedBox(height: 8),
          Text(
            embeddings.setupError!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 10),
          // Troubleshooting hints based on error type
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.orangeAccent.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 14,
                      color: Colors.orangeAccent,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Troubleshooting',
                      style: TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                if (embeddings.setupError!.contains('retrieve') ||
                    embeddings.setupError!.contains('download') ||
                    embeddings.setupError!.contains('HTTP') ||
                    embeddings.setupError!.contains('network')) ...[
                  Text(
                    '• Check your internet connection',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '• Verify you can access huggingface.co',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '• Try again — the server may be temporarily busy',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '• If this persists, try clearing the model folder:',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    Platform.isWindows
                        ? '  %LOCALAPPDATA%/front-porch-ai/embeddings/'
                        : Platform.isMacOS
                        ? '  ~/Library/Caches/front-porch-ai/embeddings/'
                        : '  ~/.cache/front-porch-ai/embeddings/',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ] else if (embeddings.setupError!.contains('onnxruntime') ||
                    embeddings.setupError!.contains('.dll')) ...[
                  Text(
                    '• A conflicting ONNX Runtime library may be installed',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '• Check for onnxruntime.dll in C:\\Windows\\System32\\',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '• Remove or rename the conflicting file and retry',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                ] else ...[
                  Text(
                    '• Try clicking Retry — transient errors often resolve',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '• If this persists, restart the application',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),

        // Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (_isDone)
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent.shade700,
                  foregroundColor: AppColors.textPrimary(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text('Done'),
              )
            else if (hasError) ...[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  embeddings.clearSetupError();
                  _startSetup();
                },
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                  foregroundColor: AppColors.textPrimary(context),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ] else
              TextButton(
                onPressed: () {
                  // Cancel the setup — release the (possibly half-warmed)
                  // session; a partial download resumes on the next try.
                  embeddings.cancelSetup();
                  Navigator.of(context).pop(false);
                },
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _startSetup() async {
    final embeddings = Provider.of<EmbeddingService>(context, listen: false);

    // Downloads the model if needed, then loads + self-tests the engine.
    final ready = await embeddings.runSetup();
    if (!mounted) return;

    if (ready) {
      setState(() => _isDone = true);
    }
    // If not ready, the error state shows via embeddings.setupError.
  }
}

/// Small helper widget for the consent dialog info rows.
class InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const InfoRow({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
