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
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/database/database.dart';
// embedding_service is not carried by the services barrel; services.dart is
// here for liveDatabase().
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/data_bank/data_bank.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Dialog for managing Data Bank entries (per-character knowledge base).
/// Supports manual text entry and file import (txt, md, json, csv, pdf).
/// Imported documents are auto-chunked into ~500-word entries for embedding.
class DataBankDialog extends StatefulWidget {
  final String characterId;
  final String characterName;

  const DataBankDialog({
    super.key,
    required this.characterId,
    required this.characterName,
  });

  @override
  State<DataBankDialog> createState() => _DataBankDialogState();
}

class _DataBankDialogState extends State<DataBankDialog> {
  List<DataBankEntry> _entries = [];
  bool _loading = true;
  bool _isEditing = false;
  String? _editingId;
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  bool _embedding = false;
  int _embeddedCount = 0;
  bool _importing = false;
  String _importStatus = '';

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries() async {
    final db = liveDatabase(context);
    final entries = await db.getDataBankEntriesForCharacter(widget.characterId);
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _deleteEntry(String id) async {
    final db = liveDatabase(context);
    await db.deleteDataBankEntry(id);
    await _loadEntries();
  }

  Future<void> _embedAll() async {
    final embeddingService = Provider.of<EmbeddingService>(
      context,
      listen: false,
    );
    final db = liveDatabase(context);

    // Ensure availability has been checked (lazy init)
    if (!embeddingService.isAvailable) {
      await embeddingService.checkAvailability();
    }

    if (!embeddingService.isAvailable) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Embedding service not available. Start the ONNX server or enable an API source.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _embedding = true;
      _embeddedCount = 0;
    });

    final needsEmbed = _entries
        .where((e) => e.embedding == null || e.dimensions == 0)
        .toList();

    for (final entry in needsEmbed) {
      final vector = await embeddingService.embed(entry.content);
      if (vector != null) {
        final bytes = Float32List.fromList(
          vector.map((d) => d.toDouble()).cast<double>().toList(),
        );
        await db.updateDataBankEntry(
          DataBankEntriesCompanion(
            id: drift.Value(entry.id),
            embedding: drift.Value(Uint8List.view(bytes.buffer)),
            dimensions: drift.Value(vector.length),
          ),
        );
        if (mounted) setState(() => _embeddedCount++);
      }
    }

    await _loadEntries();
    if (mounted) setState(() => _embedding = false);
  }

  void _startEditing([DataBankEntry? entry]) {
    setState(() {
      _isEditing = true;
      _editingId = entry?.id;
      _titleController.text = entry?.title ?? '';
      _contentController.text = entry?.content ?? '';
    });
  }

  void _cancelEditing() {
    setState(() {
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

  /// Pick a file and import its contents as Data Bank entries.
  Future<void> _importFile() async {
    final result = await GuardedPicker.pickFiles(
      context,
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: [
        ...kDataBankTextExtensions,
        ...kDataBankPdfExtensions,
      ],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final filePath = await PickerPrefs.localPathOrTemp(result.files.single);
    if (filePath == null) return;

    setState(() {
      _importing = true;
      _importStatus = 'Reading file...';
    });

    try {
      final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
      final fileName = p.basenameWithoutExtension(filePath);
      String fullText;

      if (kDataBankPdfExtensions.contains(ext)) {
        // PDFs go through the Python sidecar server
        setState(() => _importStatus = 'Extracting text from PDF...');
        fullText = await extractDataBankPdfText(filePath);
      } else {
        // Text files read directly
        fullText = await File(filePath).readAsString();
      }

      if (fullText.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File contains no extractable text.')),
          );
        }
        setState(() => _importing = false);
        return;
      }

      // Chunk the text into ~500-word segments
      setState(() => _importStatus = 'Chunking text...');
      final chunks = chunkDataBankText(fullText, maxWords: 500);

      // Insert each chunk as a Data Bank entry
      final db = liveDatabase(context);
      setState(() => _importStatus = 'Saving ${chunks.length} chunk(s)...');

      for (int i = 0; i < chunks.length; i++) {
        final chunkTitle = chunks.length == 1
            ? fileName
            : '$fileName (${i + 1}/${chunks.length})';
        await db.insertDataBankEntry(
          DataBankEntriesCompanion(
            characterId: drift.Value(widget.characterId),
            title: drift.Value(chunkTitle),
            content: drift.Value(chunks[i]),
          ),
        );
      }

      debugPrint(
        '[DataBank] Imported "$fileName": ${chunks.length} chunk(s), ${fullText.length} chars total',
      );
      await _loadEntries();
    } catch (e) {
      debugPrint('[DataBank] Import failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final embeddedEntries = _entries
        .where((e) => e.embedding != null && e.dimensions > 0)
        .length;
    final unembedded = _entries.length - embeddedEntries;

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 650,
        height: 550,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.library_books, color: Colors.purpleAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Data Bank — ${widget.characterName}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${_entries.length} entries, $embeddedEntries embedded${unembedded > 0 ? ', $unembedded need embedding' : ''}',
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),

            // Import progress indicator
            if (_importing) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.purpleAccent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _importStatus,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.purpleAccent,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            if (_isEditing)
              DataBankEditForm(
                titleController: _titleController,
                contentController: _contentController,
                isNew: _editingId == null,
                onCancel: _cancelEditing,
                onSave: _saveEntry,
              )
            else ...[
              // Action bar
              DataBankToolbar(
                importing: _importing,
                embedding: _embedding,
                embeddedCount: _embeddedCount,
                unembedded: unembedded,
                onAdd: () => _startEditing(),
                onImport: _importFile,
                onEmbed: _embedAll,
              ),
              const SizedBox(height: 4),
              const Text(
                'Supports: .txt, .md, .pdf, .json, .csv, .xml, .html, .yml',
                style: TextStyle(fontSize: 10, color: Colors.white24),
              ),
              const SizedBox(height: 8),

              // Entry list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _entries.isEmpty
                    ? const DataBankEmptyState()
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          return DataBankEntryTile(
                            entry: entry,
                            onEdit: () => _startEditing(entry),
                            onDelete: () => _deleteEntry(entry.id),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
