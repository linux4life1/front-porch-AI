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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Last-resort screen shown when startup dies before the real app can run.
/// Deliberately self-contained — it runs before the theme exists, so it pins
/// `AppColors` consts directly rather than depend on any provider or ThemeData.
///
/// Two variants, because two very different failures land here and the advice
/// for one is useless for the other:
/// - default: the database genuinely couldn't be opened (disk full, no write
///   permission, or another copy of the app holding the file);
/// - [settingsFileCorrupt]: the settings file (`shared_preferences.json`)
///   failed to parse. Startup's first prefs read happens inside the
///   database-open guard, so this used to be misreported as a database
///   failure — users were told to free disk space when the actual fix was
///   removing one damaged file. [PrefsRecovery] heals this automatically;
///   this screen is the fallback for when even that fails.
class DbInitErrorApp extends StatelessWidget {
  const DbInitErrorApp({
    super.key,
    required this.details,
    this.settingsFileCorrupt = false,
  });

  /// The caught exception's `toString()`, shown small under the advice.
  final String details;

  /// True when the failure was a settings-file parse error, not the database.
  final bool settingsFileCorrupt;

  @override
  Widget build(BuildContext context) {
    final title = settingsFileCorrupt
        ? "Front Porch AI couldn't read its settings"
        : "Front Porch AI couldn't open its database";
    final advice = settingsFileCorrupt
        ? 'The settings file (shared_preferences.json in the app\'s data '
              'folder) is damaged — this usually happens after a crash or '
              'power loss while it was being saved. Delete or rename that '
              'file, then reopen the app. Your characters and chats are '
              'stored separately and are safe; only app settings are lost.'
        : 'This is usually a full disk, missing write permission, or '
              'another copy of Front Porch AI already running. Free up '
              'space, close any other copies, then reopen the app.';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  settingsFileCorrupt
                      ? Icons.settings_backup_restore_rounded
                      : Icons.storage_rounded,
                  // theme-keep: shown before settings load, so no theme.
                  color: Colors.orangeAccent,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    // theme-keep: shown before settings load, so no theme.
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  advice,
                  textAlign: TextAlign.center,
                  // theme-keep: shown before settings load, so no theme.
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 20),
                Text(
                  details,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  // theme-keep: shown before settings load, so no theme.
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
