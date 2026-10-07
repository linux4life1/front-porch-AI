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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

/// Dialog shown after character import to let user add/edit tags.
/// Pre-populates with any tags from the V2 card data (e.g. from Chub.ai).
class TagDialog extends StatefulWidget {
  final CharacterCard character;

  const TagDialog({super.key, required this.character});

  @override
  State<TagDialog> createState() => _TagDialogState();

  /// Shows the tag dialog and returns the updated tag list (or null if skipped)
  static Future<List<String>?> show(
    BuildContext context,
    CharacterCard character,
  ) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) => TagDialog(character: character),
    );
  }
}

class _TagDialogState extends State<TagDialog> {
  late List<String> _tags;
  final _controller = TextEditingController();
  final _tagsScroll = ScrollController();
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _tags = List.from(widget.character.tags);
  }

  @override
  void dispose() {
    _controller.dispose();
    _tagsScroll.dispose();
    super.dispose();
  }

  void _addTag(String tag) {
    final trimmed = tag.trim().toLowerCase();
    if (trimmed.isNotEmpty && !_tags.contains(trimmed)) {
      setState(() {
        _tags.add(trimmed);
        _controller.clear();
        _suggestions = [];
      });
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
    });
  }

  void _updateSuggestions(String query) {
    if (query.isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final allTags = repo.allTags;
    setState(() {
      _suggestions = allTags
          .where(
            (t) =>
                t.toLowerCase().contains(query.toLowerCase()) &&
                !_tags.contains(t),
          )
          .take(8)
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // A card can carry dozens of imported tags. The dialog stops at most of
    // the screen and the chips scroll inside it, so the input and the
    // buttons are always on screen.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;
    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 450,
        constraints: BoxConstraints(maxHeight: maxHeight),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.label_outline, color: Colors.amber, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tag "${widget.character.name}"',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.character.tags.isNotEmpty
                  ? 'Tags imported from card data. Add more or edit below.'
                  : 'Add tags to organize this character.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // Current tags: a scrolling region that yields to the input and
            // the buttons when the list is long.
            if (_tags.isNotEmpty) ...[
              Flexible(
                child: Scrollbar(
                  controller: _tagsScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _tagsScroll,
                    padding: const EdgeInsets.only(right: 12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags
                          .map(
                            (tag) => Chip(
                              label: Text(
                                tag,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                              backgroundColor: const Color(0xFF374151),
                              deleteIcon: const Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.white54,
                              ),
                              onDeleted: () => _removeTag(tag),
                              side: BorderSide.none,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Tag input
            TextField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Type a tag and press Enter...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF374151),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add, color: Colors.amber),
                  onPressed: () => _addTag(_controller.text),
                ),
              ),
              onChanged: _updateSuggestions,
              onSubmitted: (value) {
                _addTag(value);
              },
            ),

            // Autocomplete suggestions
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                decoration: BoxDecoration(
                  color: const Color(0xFF374151),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        _suggestions[index],
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      leading: const Icon(
                        Icons.label,
                        size: 16,
                        color: Colors.white38,
                      ),
                      onTap: () => _addTag(_suggestions[index]),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null), // Skip
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, _tags),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Save Tags'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
