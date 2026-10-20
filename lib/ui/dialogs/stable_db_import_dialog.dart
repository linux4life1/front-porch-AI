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
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// Glassmorphic modal overlay shown on first nightly launch when a stable DB
/// is detected. Gives the user a choice to import their stable data into
/// the nightly installation before any silent copy occurs.
class StableDbImportDialog extends StatelessWidget {
  const StableDbImportDialog({super.key});

  static Future<bool> shouldShow() async {
    if (!isPreRelease) return false;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('beta_stable_import_shown') ?? false) return false;

    final docsDir = await getApplicationDocumentsDirectory();
    final betaRoot = p.join(docsDir.path, 'FrontPorchAI-Beta');
    final stableRoot = p.join(docsDir.path, 'FrontPorchAI');

    final betaDb = File(
      p.join(betaRoot, 'KoboldManager', 'front_porch_beta.db'),
    );
    final stableDb = File(
      p.join(stableRoot, 'KoboldManager', 'front_porch.db'),
    );

    return stableDb.existsSync() && !betaDb.existsSync();
  }

  static Future<String?> stableDbPath() async {
    if (!isPreRelease) return null;
    final docsDir = await getApplicationDocumentsDirectory();
    final stableRoot = p.join(docsDir.path, 'FrontPorchAI');
    final path = p.join(stableRoot, 'KoboldManager', 'front_porch.db');
    return File(path).existsSync() ? path : null;
  }

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const StableDbImportDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 540),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: InkColors.frostPanelOf(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: InkColors.frostEdgeOf(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 32,
              offset: const Offset(0, 12),
              spreadRadius: -4,
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.porchAmberOf(
                    context,
                  ).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 40,
                  color: AppColors.porchAmberOf(context),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Welcome to Front Porch AI — Nightly',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 16),

              // Body
              Text(
                'Would you like to import your stable database into this nightly '
                'app to try the new features with your existing characters '
                'and chats?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.slateMutedOf(context),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),

              // Note box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: InkColors.washOf(context, 0.04, 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: InkColors.chipEdgeOf(context)),
                ),
                child: Text(
                  'Note: your stable database will be unaffected and still '
                  'available with the stable app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.slateFaintOf(context),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => _handleSkip(context),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: InkColors.fieldEdgeOf(context),
                        width: 1,
                      ),
                      foregroundColor: InkColors.mutedTextOf(context, 0.7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Skip for now',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => _handleImport(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.porchAmberOf(context),
                      foregroundColor: AppColors.inkOn(
                        AppColors.porchAmberOf(context),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Import Stable DB',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _handleImport(BuildContext context) async {
    await _markShown();
    if (context.mounted) Navigator.of(context).pop();
    // The copy will happen when AppDatabase.instance() runs next
    // (the skip flag was not set, so the silent copy proceeds).
  }

  static Future<void> _handleSkip(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('beta_stable_import_skipped', true);
    await _markShown();
    if (context.mounted) Navigator.of(context).pop();
  }

  static Future<void> _markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('beta_stable_import_shown', true);
  }
}
