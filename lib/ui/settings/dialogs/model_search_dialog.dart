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

/// Search and pick from available models.
void showModelSearchDialog(
  BuildContext context,
  StorageService storageService,
  List<RemoteModelInfo> availableModels,
) {
  showGenericModelSearchDialog<RemoteModelInfo>(
    context,
    availableModels,
    title: 'Select Model',
    getTitle: (m) => m.name,
    getSubtitle: (m) => m.id,
    onSelected: (m) => storageService.backendSettings.setRemoteModelName(m.id),
  );
}

/// Generic searchable model picker dialog. Reused for both remote models and local .gguf files
/// so the UI/UX (search, list, styling) is identical everywhere.
void showGenericModelSearchDialog<T>(
  BuildContext context,
  List<T> availableModels, {
  required String title,
  required String Function(T) getTitle,
  required String Function(T) getSubtitle,
  required void Function(T) onSelected,
}) {
  showDialog(
    context: context,
    builder: (ctx) {
      String searchQuery = '';
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = searchQuery.isEmpty
              ? availableModels
              : availableModels.where((m) {
                  final q = searchQuery.toLowerCase();
                  final t = getTitle(m).toLowerCase();
                  final s = getSubtitle(m).toLowerCase();
                  return t.contains(q) || s.contains(q);
                }).toList();

          return AlertDialog(
            backgroundColor: AppColors.surfaceOf(context),
            title: Text(
              title,
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            content: SizedBox(
              width: 500,
              height: 450,
              child: Column(
                children: [
                  // Search bar
                  TextField(
                    autofocus: true,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search models...',
                      hintStyle: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.iconSecondary(context),
                        size: 20,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (c, i) {
                        final m = filtered[i];
                        return ListTile(
                          title: Text(
                            getTitle(m),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                            ),
                          ),
                          subtitle: Text(
                            getSubtitle(m),
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                            ),
                          ),
                          onTap: () {
                            onSelected(m);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary(context)),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
