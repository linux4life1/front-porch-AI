import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:front_porch_ai/utils/utils.dart';

class LoreExtractionService {
  /// Extracts text from a list of URLs and a list of local files.
  /// Combines them into a single massively concatenated string.
  /// Reports status via [onProgress] if provided.
  static Future<String> extractAll({
    required List<String> urls,
    required List<PlatformFile> files,
    void Function(String)? onProgress,
  }) async {
    final buffer = StringBuffer();

    // 1. Process valid URLs
    for (int i = 0; i < urls.length; i++) {
      final url = urls[i].trim();
      if (url.isEmpty ||
          (!url.startsWith('http://') && !url.startsWith('https://'))) {
        continue;
      }
      onProgress?.call('Fetching URL ${i + 1}/${urls.length}...');
      try {
        final text = await _scrapeUrl(url);
        if (text != null && text.isNotEmpty) {
          buffer.writeln('=== LORE FROM URL: $url ===');
          buffer.writeln(text);
          buffer.writeln();
        }
      } catch (e) {
        debugPrint('LoreExtractionService: Failed to scrape $url: $e');
      }
    }

    // 2. Process Local Files
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      onProgress?.call('Reading file ${file.name}...');
      try {
        final text = await _extractFromFile(file);
        if (text != null && text.isNotEmpty) {
          buffer.writeln('=== LORE FROM FILE: ${file.name} ===');
          buffer.writeln(text);
          buffer.writeln();
        }
      } catch (e) {
        debugPrint('LoreExtractionService: Failed to extract ${file.name}: $e');
      }
    }

    return buffer.toString().trim();
  }

  /// Fetches a URL, decodes the HTML, and aggressively strips garbage using CSS selectors
  /// to retain only reading content (P, H1-H6, LI).
  static Future<String?> _scrapeUrl(String urlString) async {
    try {
      final uri = Uri.tryParse(urlString);
      if (uri == null || !isSafeOutboundUrl(uri)) return null;

      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);

      // Remove structural non-content tags
      final extraneousTags = [
        'script',
        'style',
        'nav',
        'header',
        'footer',
        'aside',
        'iframe',
        'noscript',
        'form',
        'button',
      ];
      for (final tag in extraneousTags) {
        document.querySelectorAll(tag).forEach((el) => el.remove());
      }

      // Collect pure texts from readable elements
      final readableNodes = document.querySelectorAll(
        'p, h1, h2, h3, h4, h5, h6, li',
      );
      final textBuffer = StringBuffer();

      for (final node in readableNodes) {
        final t = node.text.trim();
        // Skip tiny navigation elements or empty lines that survived the purge
        if (t.length > 5) {
          textBuffer.writeln(t);
        }
      }

      return textBuffer.toString();
    } catch (e) {
      debugPrint('LoreExtractionService: Error on URL $urlString - $e');
      return null;
    }
  }

  /// Reads a PlatformFile either as a PDF using syncfusion or plain UTF-8 for everything else.
  static Future<String?> _extractFromFile(PlatformFile file) async {
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final extension = file.extension?.toLowerCase() ?? '';

      if (extension == 'pdf') {
        final document = PdfDocument(inputBytes: bytes);
        final extractor = PdfTextExtractor(document);
        final text = extractor.extractText();
        document.dispose();
        return text;
      } else {
        // Assume UTF-8 readable text (.txt, .md, .json, .csv)
        return utf8.decode(bytes, allowMalformed: true);
      }
    } catch (e) {
      debugPrint('LoreExtractionService: Error reading file ${file.name} - $e');
      return null;
    }
  }
}
