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
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as drift;
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:front_porch_ai/database/database.dart';
// embedding_service is not carried by the services barrel; services.dart is
// here for liveDatabase().
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/services.dart';
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

  // ── File Import ──────────────────────────────────────────────────────

  /// Supported file extensions for import.
  static const _textExtensions = [
    'txt',
    'md',
    'json',
    'csv',
    'log',
    'xml',
    'html',
    'yml',
    'yaml',
  ];
  static const _pdfExtensions = ['pdf'];

  /// Pick a file and import its contents as Data Bank entries.
  Future<void> _importFile() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: [..._textExtensions, ..._pdfExtensions],
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

      if (_pdfExtensions.contains(ext)) {
        // PDFs go through the Python sidecar server
        setState(() => _importStatus = 'Extracting text from PDF...');
        fullText = await _extractPdfText(filePath);
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
      final chunks = _chunkText(fullText, maxWords: 500);

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

  /// Extract text from a PDF in-process (Syncfusion, an existing dep).
  ///
  /// Replaced an HTTP call to the embedding server's `/v1/extract-text` —
  /// an endpoint only the ORIGINAL Python embed server implemented. The
  /// Rust rewrite never had it, so PDF import has been silently broken
  /// (30s timeout → "Import failed") for months; the sidecar retirement
  /// sweep found it. Runs in an isolate — extraction of a big PDF is
  /// CPU-heavy and would freeze the dialog.
  Future<String> _extractPdfText(String filePath) async {
    final bytes = await File(filePath).readAsBytes();
    final text = await Isolate.run(() {
      final doc = PdfDocument(inputBytes: bytes);
      try {
        return PdfTextExtractor(doc).extractText();
      } finally {
        doc.dispose();
      }
    });
    debugPrint('[DataBank] PDF extracted: ${text.length} chars');
    return text;
  }

  /// Split text into chunks of approximately [maxWords] words each.
  /// Tries to break at paragraph boundaries for cleaner splits.
  static List<String> _chunkText(String text, {int maxWords = 500}) {
    // Normalize whitespace
    final normalized = text.replaceAll('\r\n', '\n').trim();

    // If the text is small enough, return as a single chunk
    final wordCount = normalized.split(RegExp(r'\s+')).length;
    if (wordCount <= maxWords) return [normalized];

    // Split into paragraphs first
    final paragraphs = normalized.split(RegExp(r'\n\s*\n'));
    final chunks = <String>[];
    final currentChunk = StringBuffer();
    int currentWords = 0;

    for (final para in paragraphs) {
      final paraWords = para.trim().split(RegExp(r'\s+')).length;

      // If adding this paragraph would exceed the limit, save current chunk
      if (currentWords > 0 && currentWords + paraWords > maxWords) {
        chunks.add(currentChunk.toString().trim());
        currentChunk.clear();
        currentWords = 0;
      }

      // If a single paragraph is larger than maxWords, split it by sentences
      if (paraWords > maxWords) {
        final sentences = para.split(RegExp(r'(?<=[.!?])\s+'));
        for (final sentence in sentences) {
          final sentenceWords = sentence.trim().split(RegExp(r'\s+')).length;
          if (currentWords > 0 && currentWords + sentenceWords > maxWords) {
            chunks.add(currentChunk.toString().trim());
            currentChunk.clear();
            currentWords = 0;
          }
          if (currentChunk.isNotEmpty) currentChunk.write(' ');
          currentChunk.write(sentence.trim());
          currentWords += sentenceWords;
        }
      } else {
        if (currentChunk.isNotEmpty) currentChunk.write('\n\n');
        currentChunk.write(para.trim());
        currentWords += paraWords;
      }
    }

    // Don't forget the last chunk
    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.toString().trim());
    }

    return chunks.isEmpty ? [normalized] : chunks;
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
              _buildEditForm()
            else ...[
              // Action bar
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _startEditing(),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _importing ? null : _importFile,
                    icon: const Icon(Icons.file_upload, size: 16),
                    label: const Text('Import File'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF374151),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  if (unembedded > 0)
                    ElevatedButton.icon(
                      onPressed: _embedding ? null : _embedAll,
                      icon: _embedding
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.memory, size: 16),
                      label: Text(
                        _embedding
                            ? '$_embeddedCount/$unembedded'
                            : 'Embed ($unembedded)',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF374151),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
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
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.library_books_outlined,
                              size: 48,
                              color: Colors.white12,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No entries yet',
                              style: TextStyle(
                                color: Colors.white30,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Add text or import files to build a knowledge base.\nRAG retrieves matching entries during conversations.',
                              style: TextStyle(
                                color: Colors.white24,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, index) {
                          final entry = _entries[index];
                          final hasEmbed =
                              entry.embedding != null && entry.dimensions > 0;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      hasEmbed
                                          ? Icons.check_circle
                                          : Icons.circle_outlined,
                                      size: 14,
                                      color: hasEmbed
                                          ? Colors.greenAccent
                                          : Colors.white24,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        entry.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${entry.content.split(RegExp(r'\\s+')).length}w',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        color: Colors.white24,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit,
                                        size: 14,
                                        color: Colors.white38,
                                      ),
                                      onPressed: () => _startEditing(entry),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete,
                                        size: 14,
                                        color: Colors.redAccent,
                                      ),
                                      onPressed: () => _deleteEntry(entry.id),
                                      constraints: const BoxConstraints(),
                                      padding: const EdgeInsets.all(4),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.content.length > 150
                                      ? '${entry.content.substring(0, 150)}...'
                                      : entry.content,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
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
