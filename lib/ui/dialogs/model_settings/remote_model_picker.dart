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
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Fetches [apiUrl]'s model list behind a loading spinner and lets the user
/// pick one; returns the chosen id, or null when cancelled or nothing could
/// be listed (the reason goes to a snackbar). [currentModel] is marked.
///
/// Uses the override-form fetch so the live service config is never mutated
/// by a mere list browse (the old configure()-then-fetch pattern silently
/// re-routed active chat traffic AND carried the previous backend's model
/// name into the new provider).
Future<String?> pickRemoteModel(
  BuildContext context, {
  required String apiUrl,
  required String apiKey,
  required String currentModel,
}) async {
  final openRouter = Provider.of<OpenRouterService>(context, listen: false);

  // Show loading dialog
  if (!context.mounted) return null;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  List<RemoteModelInfo> models;
  try {
    models = await openRouter.fetchAvailableModels(
      apiUrl: apiUrl,
      apiKey: apiKey,
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context); // dismiss loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to fetch models: $e')));
    }
    return null;
  }

  if (!context.mounted) return null;
  Navigator.pop(context); // dismiss loading

  if (models.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No models available. Check your API URL and key.'),
      ),
    );
    return null;
  }

  // Show the model picker dialog
  return showDialog<String>(
    context: context,
    builder: (_) =>
        RemoteModelPickerDialog(models: models, currentModel: currentModel),
  );
}

/// The searchable remote-model list. Pops with the chosen model id.
class RemoteModelPickerDialog extends StatefulWidget {
  const RemoteModelPickerDialog({
    super.key,
    required this.models,
    required this.currentModel,
  });

  final List<RemoteModelInfo> models;
  final String currentModel;

  @override
  State<RemoteModelPickerDialog> createState() =>
      _RemoteModelPickerDialogState();
}

class _RemoteModelPickerDialogState extends State<RemoteModelPickerDialog> {
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filtered = searchQuery.isEmpty
        ? widget.models
        : widget.models
              .where(
                (m) => m.id.toLowerCase().contains(searchQuery.toLowerCase()),
              )
              .toList();

    return AlertDialog(
      backgroundColor: AppColors.cardOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Select Model',
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            autofocus: true,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: 'Search models...',
              hintStyle: TextStyle(color: AppColors.textTertiary(context)),
              prefixIcon: Icon(
                Icons.search,
                color: AppColors.iconSecondary(context),
                size: 18,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              isDense: true,
            ),
            onChanged: (val) => setState(() => searchQuery = val),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        height: 400,
        child: filtered.isEmpty
            ? Center(
                child: Text(
                  'No models match "$searchQuery"',
                  style: TextStyle(color: AppColors.textTertiary(context)),
                ),
              )
            : ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, index) {
                  final model = filtered[index];
                  final isSelected = model.id == widget.currentModel;
                  return ListTile(
                    dense: true,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    title: Text(
                      model.id,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.formAccentOf(context)
                            : AppColors.textPrimary(context),
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Row(
                      children: [
                        if (model.isFree)
                          Container(
                            margin: const EdgeInsets.only(right: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              // theme-keep: pricing legend hue (FREE badge), not chrome
                              color: Colors.green.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'FREE',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Flexible(
                          child: Text(
                            model.pricingLabel,
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle,
                            color: AppColors.formAccentOf(context),
                            size: 18,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, model.id),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
      ],
    );
  }
}
