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
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The Data Bank add/edit form: title, content, Cancel / Save. Fills the
/// rest of the dialog's column.
class DataBankEditForm extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController contentController;

  /// True for "New Entry", false for "Edit Entry".
  final bool isNew;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const DataBankEditForm({
    super.key,
    required this.titleController,
    required this.contentController,
    required this.isNew,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isNew ? 'New Entry' : 'Edit Entry',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: titleController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Title',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: 'e.g., "Backstory", "World Lore", "Character History"',
              hintStyle: TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Color(0xFF374151),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: AppTextField(
              controller: contentController,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Content',
                labelStyle: TextStyle(color: Colors.white54),
                hintText: 'Enter knowledge text...',
                hintStyle: TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Color(0xFF374151),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purpleAccent,
                ),
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
