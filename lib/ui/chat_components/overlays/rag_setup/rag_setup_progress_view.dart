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

import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The running / failed / finished view of RAG setup, driven by
/// [embeddings]' setup status. [onRetry] restarts setup after the error has
/// been cleared.
class RagSetupProgressView extends StatelessWidget {
  final EmbeddingService embeddings;
  final bool isDone;
  final VoidCallback onRetry;

  const RagSetupProgressView({
    super.key,
    required this.embeddings,
    required this.isDone,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
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
            if (isDone)
              Icon(
                Icons.check_circle,
                color: StatusColors.successOf(context),
                size: 28,
              )
            else if (hasError)
              Icon(
                Icons.error_outline,
                color: StatusColors.dangerOf(context),
                size: 28,
              )
            else
              SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: ChatColors.memoryOf(context),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isDone
                    ? 'Setup Complete'
                    : hasError
                    ? 'Setup Failed'
                    : 'Setting Up Memory...',
                style: TextStyle(
                  color: isDone
                      ? StatusColors.successOf(context)
                      : hasError
                      ? StatusColors.dangerOf(context)
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
                  ? StatusColors.dangerOf(context).withValues(alpha: 0.3)
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
                      ? StatusColors.dangerOf(context)
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ChatColors.memoryOf(context),
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
              if (!showProgress && !hasError && !isDone) ...[
                SizedBox(height: 10),
                ClipRRect(
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: AppColors.borderOf(
                      context,
                    ).withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      ChatColors.memoryOf(context),
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
            style: TextStyle(
              color: StatusColors.dangerOf(context),
              fontSize: 11,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 10),
          // Troubleshooting hints based on error type
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: StatusColors.warningOf(context).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: StatusColors.warningOf(context).withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.lightbulb_outline,
                      size: 14,
                      color: StatusColors.warningOf(context),
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Troubleshooting',
                      style: TextStyle(
                        color: StatusColors.warningOf(context),
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
            if (isDone)
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: StatusColors.successFillOf(context),
                  foregroundColor: StatusColors.onFill,
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
                  onRetry();
                },
                icon: Icon(Icons.refresh, size: 16),
                label: Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChatColors.memoryOf(context),
                  foregroundColor: StatusColors.onFill,
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
}
