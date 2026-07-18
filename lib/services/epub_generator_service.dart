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

import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';
import 'package:front_porch_ai/models/story_project.dart';

class FormattedEbook {
  final StoryProject project;
  final List<int> bytes;

  FormattedEbook({required this.project, required this.bytes});
}

/// Utility for compiling a Porch Story project into a standard, offline-compliant `.epub` file.
class EpubGeneratorService {
  /// Builds a fully-compliant EPUB 2 zip container entirely in memory.
  static Future<FormattedEbook?> generateEpub(StoryProject project) async {
    final archive = Archive();
    final uuid = const Uuid().v4();

    // 1. mimetype (MUST be at root, MUST be uncompressed, MUST be first)
    final mimetypeBytes = utf8.encode('application/epub+zip');
    final mimetypeParam = ArchiveFile.noCompress(
      'mimetype',
      mimetypeBytes.length,
      mimetypeBytes,
    );
    archive.addFile(mimetypeParam);

    // 2. META-INF/container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    archive.addFile(
      ArchiveFile(
        'META-INF/container.xml',
        containerXml.length,
        utf8.encode(containerXml),
      ),
    );

    // 3. Prepare content structure
    final chapterHtmlFiles = <String, String>{};
    final navPoints = <String>[];
    int playOrder = 1;

    // Add Title Page
    chapterHtmlFiles['title.html'] = _buildHtmlWrap(project.title, '''
      <div style="text-align: center; margin-top: 25%;">
        <h1>${_escapeXml(project.title)}</h1>
        <p><i>A Story by Front Porch AI</i></p>
        <br/><br/>
        <p>${_escapeXml(project.concept)}</p>
      </div>
    ''');

    navPoints.add('''
      <navPoint id="navPoint-$playOrder" playOrder="$playOrder">
        <navLabel><text>Title Page</text></navLabel>
        <content src="Text/title.html"/>
      </navPoint>
    ''');
    playOrder++;

    // Add Acts / Chapters
    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      final scenes = project.scenes[actIdx] ?? [];

      final buffer = StringBuffer();
      buffer.writeln('<h2>Act ${act.number}: ${_escapeXml(act.title)}</h2>');
      buffer.writeln('<p><i>${_escapeXml(act.description)}</i></p><hr/>');

      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final scene = scenes[sceneIdx];
        final sId = '$actIdx-$sceneIdx';
        final beats = project.beats[sId] ?? [];

        buffer.writeln('<br/><h3>${_escapeXml(scene.title)}</h3>');

        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final bId = '$sId-$beatIdx';
          final prose =
              project.prose[bId]?.final_ ?? project.prose[bId]?.draft ?? '';
          if (prose.trim().isNotEmpty) {
            // Split into paragraphs for proper eBook indentation flow
            final paragraphs = prose.split('\n\n');
            for (final p in paragraphs) {
              if (p.trim().isNotEmpty) {
                buffer.writeln('<p>${_escapeXml(p.trim())}</p>');
              }
            }
          }
        }
      }

      final chapterFilename = 'act_${actIdx + 1}.html';
      chapterHtmlFiles[chapterFilename] = _buildHtmlWrap(
        'Act ${act.number}',
        buffer.toString(),
      );

      navPoints.add('''
        <navPoint id="navPoint-$playOrder" playOrder="$playOrder">
          <navLabel><text>Act ${act.number}: ${_escapeXml(act.title)}</text></navLabel>
          <content src="Text/$chapterFilename"/>
        </navPoint>
      ''');
      playOrder++;
    }

    // Write Text folders to archive
    for (final entry in chapterHtmlFiles.entries) {
      final path = 'OEBPS/Text/${entry.key}';
      final bytes = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    // 4. Create content.opf
    final manifestItems = StringBuffer();
    final spineItems = StringBuffer();

    manifestItems.writeln(
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
    );
    manifestItems.writeln(
      '<item id="title" href="Text/title.html" media-type="application/xhtml+xml"/>',
    );
    spineItems.writeln('<itemref idref="title"/>');

    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      manifestItems.writeln(
        '<item id="act_${actIdx + 1}" href="Text/act_${actIdx + 1}.html" media-type="application/xhtml+xml"/>',
      );
      spineItems.writeln('<itemref idref="act_${actIdx + 1}"/>');
    }

    final contentOpf =
        '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
    <dc:title>${_escapeXml(project.title)}</dc:title>
    <dc:creator opf:role="aut">Front Porch AI</dc:creator>
    <dc:language>en</dc:language>
    <dc:identifier id="BookId" opf:scheme="UUID">urn:uuid:$uuid</dc:identifier>
  </metadata>
  <manifest>
$manifestItems  </manifest>
  <spine toc="ncx">
$spineItems  </spine>
</package>''';

    archive.addFile(
      ArchiveFile(
        'OEBPS/content.opf',
        utf8.encode(contentOpf).length,
        utf8.encode(contentOpf),
      ),
    );

    // 5. Create toc.ncx
    final tocNcx =
        '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="urn:uuid:$uuid"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle>
    <text>${_escapeXml(project.title)}</text>
  </docTitle>
  <navMap>
${navPoints.join('\n')}
  </navMap>
</ncx>''';

    archive.addFile(
      ArchiveFile(
        'OEBPS/toc.ncx',
        utf8.encode(tocNcx).length,
        utf8.encode(tocNcx),
      ),
    );

    // 6. Zip encode the final byte stream
    final encodedZip = ZipEncoder().encode(archive);

    return FormattedEbook(project: project, bytes: encodedZip);
  }

  static String _buildHtmlWrap(String title, String body) {
    return '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
  <title>${_escapeXml(title)}</title>
  <style type="text/css">
    body { font-family: serif; line-height: 1.5; }
    p { margin-top: 0; margin-bottom: 0; text-indent: 1.5em; }
    h1, h2, h3 { text-align: center; }
  </style>
</head>
<body>
  $body
</body>
</html>''';
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
