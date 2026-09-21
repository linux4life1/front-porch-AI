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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/web_search_settings.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'wiki_url_field.dart';

/// Porch Life library: add a wiki URL, then an accordion of every saved host.
class WikiUrlList extends StatefulWidget {
  const WikiUrlList({super.key, this.fieldKey = 'wiki-url-field'});

  final String fieldKey;

  @override
  State<WikiUrlList> createState() => _WikiUrlListState();
}

class _WikiUrlListState extends State<WikiUrlList> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final saved = storage.webSearchSettings.savedWikiUrls;
    return Padding(
      key: const Key('wiki-url-list'),
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WikiUrlField(storage: storage, fieldKey: widget.fieldKey),
          InkWell(
            key: const Key('wiki-saved-accordion'),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      saved.isEmpty
                          ? 'Saved wikis'
                          : 'Saved wikis (${saved.length})',
                      style: TextStyle(
                        color: AppColors.textSecondary(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.iconSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          if (_open) ...[
            if (saved.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'None saved yet.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary(context),
                  ),
                ),
              )
            else
              for (final url in saved)
                _SavedWikiRow(storage: storage, url: url),
          ],
        ],
      ),
    );
  }
}

class _SavedWikiRow extends StatelessWidget {
  const _SavedWikiRow({required this.storage, required this.url});

  final StorageService storage;
  final String url;

  @override
  Widget build(BuildContext context) {
    final host = wikiHostLabel(url);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              host,
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 13,
              ),
            ),
          ),
          IconButton(
            key: Key('wiki-saved-remove-$host'),
            tooltip: 'Remove',
            icon: Icon(
              Icons.close,
              size: 18,
              color: AppColors.iconSecondary(context),
            ),
            onPressed: () => storage.webSearchSettings.removeSavedWikiUrl(url),
          ),
        ],
      ),
    );
  }
}
