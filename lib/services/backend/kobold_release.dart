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

// The KoboldCpp release on GitHub this machine's engine is compared with.

import 'dart:convert';

import 'package:http/http.dart' as http;

/// The last GitHub release lookup and whether one is running. [builtFor]
/// is the build the lookup was for: the ROCm build has its own release, so
/// a lookup for another build says nothing about it.
class KoboldReleaseCheck {
  KoboldReleaseCheck(this._notify);

  final void Function() _notify;

  String? version;
  int? assetSize;
  String? builtFor;
  bool checking = false;
  String? error;

  /// Looks up the release. The Linux ROCm build lives under the rolling
  /// `rocm-rolling` tag (what koboldai.org/cpplinuxrocm serves), never in
  /// releases/latest — version-checking it against latest lied about what
  /// was installed. [exeName] is read once the answer is in.
  Future<void> run({
    required bool rocmRolling,
    required String Function() exeName,
  }) async {
    if (checking) return;
    checking = true;
    error = null;
    _notify();
    try {
      final client = http.Client();
      try {
        final releasePath = rocmRolling
            ? 'releases/tags/rocm-rolling'
            : 'releases/latest';
        final response = await client
            .get(
              Uri.parse(
                'https://api.github.com/repos/LostRuins/koboldcpp/$releasePath',
              ),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final tag = (body['tag_name'] as String?) ?? '';
          version = tag.replaceFirst(RegExp(r'^[vV]'), '');
          final name = exeName();
          builtFor = name;
          assetSize = null;
          for (final a in (body['assets'] as List?) ?? []) {
            if (a['name'] == name) {
              assetSize = a['size'] as int?;
              // A rolling tag never changes name — the asset's rebuild
              // date is the real version identity.
              final updated = a['updated_at'] as String?;
              if (releasePath != 'releases/latest' && updated != null) {
                version = '$tag (${updated.split('T').first})';
              }
              break;
            }
          }
        } else {
          error = 'GitHub API: HTTP ${response.statusCode}';
        }
      } finally {
        client.close();
      }
    } catch (_) {
      error = 'Could not check for updates';
    } finally {
      checking = false;
      _notify();
    }
  }
}
