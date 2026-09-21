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

/// File pick, PDF extract, and chunking for Data Bank import.
/// Supported file extensions for import.
const _textExtensions = [
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
const _pdfExtensions = ['pdf'];

/// Split text into chunks of approximately [maxWords] words each.
/// Tries to break at paragraph boundaries for cleaner splits.
List<String> _chunkText(String text, {int maxWords = 500}) {
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

extension _DataBankDialogImport on _DataBankDialogState {
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

    rebuildState(() {
      _importing = true;
      _importStatus = 'Reading file...';
    });

    try {
      final ext = p.extension(filePath).toLowerCase().replaceAll('.', '');
      final fileName = p.basenameWithoutExtension(filePath);
      String fullText;

      if (_pdfExtensions.contains(ext)) {
        // PDFs go through the Python sidecar server
        rebuildState(() => _importStatus = 'Extracting text from PDF...');
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
        rebuildState(() => _importing = false);
        return;
      }

      // Chunk the text into ~500-word segments
      rebuildState(() => _importStatus = 'Chunking text...');
      final chunks = _chunkText(fullText, maxWords: 500);

      // Insert each chunk as a Data Bank entry
      final db = liveDatabase(context);
      rebuildState(() => _importStatus = 'Saving ${chunks.length} chunk(s)...');

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
      if (mounted) rebuildState(() => _importing = false);
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
}
