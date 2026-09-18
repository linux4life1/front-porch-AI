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

part of 'data_bank_dialog.dart';

/// Add/edit form and its save path.
extension _DataBankDialogEditor on _DataBankDialogState {
  void _startEditing([DataBankEntry? entry]) {
    rebuildState(() {
      _isEditing = true;
      _editingId = entry?.id;
      _titleController.text = entry?.title ?? '';
      _contentController.text = entry?.content ?? '';
    });
  }

  void _cancelEditing() {
    rebuildState(() {
      _isEditing = false;
      _editingId = null;
      _titleController.clear();
      _contentController.clear();
    });
  }

  Future<void> _saveEntry() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty || content.isEmpty) return;

    final db = liveDatabase(context);

    if (_editingId != null) {
      await db.updateDataBankEntry(
        DataBankEntriesCompanion(
          id: drift.Value(_editingId!),
          title: drift.Value(title),
          content: drift.Value(content),
          embedding: const drift.Value(null),
          dimensions: const drift.Value(0),
        ),
      );
    } else {
      await db.insertDataBankEntry(
        DataBankEntriesCompanion(
          characterId: drift.Value(widget.characterId),
          title: drift.Value(title),
          content: drift.Value(content),
        ),
      );
    }

    _cancelEditing();
    await _loadEntries();
  }

  Widget _buildEditForm() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingId == null ? 'New Entry' : 'Edit Entry',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: _titleController,
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
              controller: _contentController,
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
                onPressed: _cancelEditing,
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: _saveEntry,
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
