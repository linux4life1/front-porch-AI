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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

const String kWikiUrlBlurb =
    'Looks up this wiki only (MediaWiki / Fandom). Not Google.';

/// Add-URL field for the Porch Life wiki library.
class WikiUrlField extends StatefulWidget {
  const WikiUrlField({
    super.key,
    required this.storage,
    this.fieldKey = 'wiki-url-field',
  });

  final StorageService storage;
  final String fieldKey;

  @override
  State<WikiUrlField> createState() => _WikiUrlFieldState();
}

class _WikiUrlFieldState extends State<WikiUrlField> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      setState(() => _error = null);
      return;
    }
    final ok = await widget.storage.webSearchSettings.addSavedWikiUrl(url);
    if (!mounted) return;
    setState(() {
      _error = ok ? null : 'That is not a MediaWiki / Fandom URL.';
      if (ok) _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key(widget.fieldKey),
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Wiki URL',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _controller,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'https://bleach.fandom.com/',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
            ),
            onSubmitted: (_) => _save(),
            onEditingComplete: _save,
          ),
          const SizedBox(height: 6),
          Text(
            kWikiUrlBlurb,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.textSecondary(context),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.negativeAccentOf(context),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.porchAmberOf(context),
                foregroundColor: AppColors.onChaosAccent,
              ),
              onPressed: _save,
              child: const Text('Save wiki'),
            ),
          ),
        ],
      ),
    );
  }
}
