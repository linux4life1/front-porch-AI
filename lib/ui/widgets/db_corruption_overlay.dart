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
import 'package:front_porch_ai/ui/theme/theme.dart';

/// A backup file with its stat read off the build path.
typedef BackupListing = ({File file, FileStat stat});

/// Full-screen "Database Issue Detected" card shown when the post-first-frame
/// integrity check fails: lists [backups] to restore from, or lets the user
/// continue without restoring. A direct child of the app's home Stack.
class DbCorruptionOverlay extends StatelessWidget {
  const DbCorruptionOverlay({
    super.key,
    required this.backups,
    required this.onRestore,
    required this.onContinue,
  });

  final List<BackupListing> backups;
  final ValueChanged<File> onRestore;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Material(
        color: AppColors.backgroundOf(context),
        child: Center(
          child: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      // theme-keep: the warning badge's gradient, white glyph on it in both modes.
                      colors: [Colors.red.shade700, Colors.orange.shade600],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        // theme-keep: the warning badge's red glow.
                        color: Colors.red.withValues(alpha: 0.3),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 40,
                    color: InkColors.onImage,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Database Issue Detected',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'An integrity check found possible corruption.\n'
                  'This can happen after a power failure or crash.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: InkColors.mutedTextOf(context, 0.5),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                if (backups.isNotEmpty) ...[
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.hairlineOf(context, 0.1),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Available Backups',
                          style: TextStyle(
                            color: InkColors.mutedTextOf(context, 0.7),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: backups.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final (:file, :stat) = backups[index];
                              final age = DateTime.now().difference(
                                stat.modified,
                              );
                              final sizeKb = (stat.size / 1024).toStringAsFixed(
                                0,
                              );
                              String ageStr;
                              if (age.inDays > 0) {
                                ageStr = '${age.inDays}d ago';
                              } else if (age.inHours > 0) {
                                ageStr = '${age.inHours}h ago';
                              } else {
                                ageStr = '${age.inMinutes}m ago';
                              }
                              return InkWell(
                                onTap: () => onRestore(file),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.hairlineOf(context, 0.03),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.restore,
                                        size: 18,
                                        color: AppColors.porchAmberOf(context),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          ageStr,
                                          style: TextStyle(
                                            color: AppColors.textPrimary(
                                              context,
                                            ),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '$sizeKb KB',
                                        style: TextStyle(
                                          color: InkColors.mutedTextOf(
                                            context,
                                            0.4,
                                          ),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: StatusColors.cautionOf(
                          context,
                        ).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: StatusColors.cautionOf(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No backups available to restore from.',
                            style: TextStyle(
                              color: InkColors.mutedTextOf(context, 0.6),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Continue anyway
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: onContinue,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: InkColors.mutedTextOf(context, 0.6),
                    ),
                    child: const Text('Continue Without Restoring'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
