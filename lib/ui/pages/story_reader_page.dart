// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
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

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:front_porch_ai/ui/widgets/custom_page_flip.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/story_narration_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/models/story_project.dart';

/// A book-like reader for completed Porch Stories with paper aesthetic
/// and page-by-page navigation.
class StoryReaderPage extends StatefulWidget {
  final String projectId;
  const StoryReaderPage({super.key, required this.projectId});

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  final _flipKey = GlobalKey<CustomPageFlipState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentPage = 0;
  List<_BookPage>? _pages; // Null when not yet calculated
  BoxConstraints? _lastConstraints;
  bool _isFirstLoad = true;
  bool _lastIsTwoPageSpread = false;

  late AudioPlayer _ambientPlayer;
  late AudioPlayer _sfxPlayer;
  bool _isAudioPlaying = true;
  bool _isAudioMuted = true; // explicitly muted by default per user request

  bool _isReadingAlong = false;
  int _bufferedPageCount = 0;

  @override
  void initState() {
    super.initState();
    _ambientPlayer = AudioPlayer();
    _sfxPlayer = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      await _ambientPlayer.setReleaseMode(ReleaseMode.loop);
      // Try to play ambient background
      final assetSource = AssetSource('audio/ambient_reading.wav');
      await _ambientPlayer.setSource(assetSource);
      await _ambientPlayer.setVolume(0.3);
      if (_isAudioPlaying && !_isAudioMuted) {
        await _ambientPlayer.resume();
      }
    } catch (e) {
      debugPrint('[StoryReader] Audio init error: $e');
    }
  }

  Future<void> _playPageTurn() async {
    if (_isAudioMuted) return;
    try {
      await _sfxPlayer.play(AssetSource('audio/page_turn.wav'), volume: 0.5);
    } catch (_) {}
  }

  void _toggleAudio() {
    setState(() {
      _isAudioMuted = !_isAudioMuted;
      if (_isAudioMuted) {
        _ambientPlayer.pause();
      } else if (_isAudioPlaying) {
        _ambientPlayer.resume();
      }
    });
  }

  @override
  void dispose() {
    _isReadingAlong = false;
    // ensure TTS stops on exit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Provider.of<TtsService>(context, listen: false).stop();
      } catch (_) {}
    });
    _ambientPlayer.dispose();
    _sfxPlayer.dispose();
    _readAlongPlayer?.dispose();
    super.dispose();
  }

  // Read-along audio player (separate from ambient)
  AudioPlayer? _readAlongPlayer;

  /// Get the text content for a given flip-page index.
  String _getPageText(int flipPage) {
    if (_pages == null) return '';
    final width = MediaQuery.of(context).size.width;
    final isTwoPageSpread = width > 800;

    if (isTwoPageSpread) {
      final leftIdx = flipPage * 2;
      final rightIdx = leftIdx + 1;
      final buf = StringBuffer();
      if (leftIdx < _pages!.length) {
        buf.write('${_pages![leftIdx].title}. ${_pages![leftIdx].body}\n\n');
      }
      if (rightIdx < _pages!.length) {
        buf.write('${_pages![rightIdx].title}. ${_pages![rightIdx].body}');
      }
      return buf.toString();
    } else {
      if (flipPage < _pages!.length) {
        return '${_pages![flipPage].title}. ${_pages![flipPage].body}';
      }
      return '';
    }
  }

  /// Generate audio for a page, using per-character voices for dialogue
  /// segments, stitched into one WAV. Delegates to the shared
  /// [StoryNarrationService] (the same engine the web read-to-me uses).
  Future<File?> _generatePageAudio(
    String pageText,
    TtsService tts,
    List<StoryCastMember> cast,
  ) {
    return StoryNarrationService.synthesizeStitchedWav(
      pageText,
      cast,
      tts,
      isCancelled: () => !_isReadingAlong,
    );
  }

  Future<void> _startReadAlong() async {
    if (_isReadingAlong || _pages == null) return;
    setState(() => _isReadingAlong = true);

    final tts = Provider.of<TtsService>(context, listen: false);
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    final cast = project?.cast ?? [];

    final flipCount = _getFlipPageCount();
    const bufferDepth = 3; // How many pages ahead to pre-generate

    // Buffer: map of page index -> single stitched audio file
    final Map<int, File?> audioBuffer = {};
    _bufferedPageCount = 0;

    // Background buffer filler — runs concurrently with playback
    int nextPageToBuffer = _currentPage;
    bool bufferDone = false;

    Future<void> fillBuffer() async {
      while (_isReadingAlong && !bufferDone) {
        if (nextPageToBuffer >= flipCount) {
          bufferDone = true;
          break;
        }
        // Only buffer ahead by bufferDepth from current playback position
        if (nextPageToBuffer - _currentPage >= bufferDepth) {
          await Future.delayed(const Duration(milliseconds: 200));
          continue;
        }
        final pageIdx = nextPageToBuffer;
        nextPageToBuffer++;

        final text = _getPageText(pageIdx);
        if (text.trim().isEmpty) {
          audioBuffer[pageIdx] = null;
          continue;
        }

        final file = await _generatePageAudio(text, tts, cast);
        if (!_isReadingAlong) break;
        audioBuffer[pageIdx] = file;
        if (mounted) {
          setState(() {
            _bufferedPageCount =
                audioBuffer.length - 1; // -1 for the page currently playing
          });
        }
      }
    }

    // Start the buffer filler concurrently
    final bufferFuture = fillBuffer();

    // Wait for the first page to be buffered
    while (!audioBuffer.containsKey(_currentPage) && _isReadingAlong) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Playback loop
    while (_isReadingAlong && _currentPage < flipCount) {
      if (!audioBuffer.containsKey(_currentPage)) {
        // Wait for buffer to catch up
        while (!audioBuffer.containsKey(_currentPage) && _isReadingAlong) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        continue;
      }

      final audioFile = audioBuffer[_currentPage];
      if (audioFile != null && audioFile.existsSync()) {
        final segPlayer = AudioPlayer();
        final completer = Completer<void>();
        final sub = segPlayer.onPlayerComplete.listen((_) {
          if (!completer.isCompleted) completer.complete();
        });

        try {
          await segPlayer.play(DeviceFileSource(audioFile.path));
          await completer.future;
        } catch (e) {
          debugPrint('[ReadAlong] Playback error: $e');
        } finally {
          await sub.cancel();
          await segPlayer.dispose();
        }
      }

      if (!_isReadingAlong) break;

      // Clean up played page from buffer to free memory
      audioBuffer.remove(_currentPage);
      if (mounted) {
        setState(() {
          _bufferedPageCount = audioBuffer.length;
        });
      }

      // Advance to next page
      if (_currentPage < flipCount - 1) {
        _flipKey.currentState?.nextPage();
        await Future.delayed(const Duration(milliseconds: 800));
      } else {
        break; // End of story
      }
    }

    bufferDone = true;
    await bufferFuture; // Clean up the buffer filler

    _readAlongPlayer?.stop();
    if (mounted) setState(() => _isReadingAlong = false);
  }

  void _stopReadAlong() {
    _isReadingAlong = false;
    _readAlongPlayer?.stop();
    Provider.of<TtsService>(context, listen: false).stop();
    setState(() {});
  }

  // ── Scene regeneration from reader ──
  bool _isRegenerating = false;

  /// Returns the scene metadata (actIndex, sceneIndex) for the current page, or null if not a prose page.
  ({int actIndex, int sceneIndex})? _getCurrentSceneMeta() {
    if (_pages == null) return null;
    final width = MediaQuery.of(context).size.width;
    final isTwoPageSpread = width > 800;

    final pageIdx = isTwoPageSpread ? _currentPage * 2 : _currentPage;
    if (pageIdx >= _pages!.length) return null;

    final page = _pages![pageIdx];
    if (page.actIndex == null || page.sceneIndex == null) return null;
    return (actIndex: page.actIndex!, sceneIndex: page.sceneIndex!);
  }

  Future<void> _regenCurrentScene() async {
    final meta = _getCurrentSceneMeta();
    if (meta == null) return;

    final repo = Provider.of<StoryRepository>(context, listen: false);
    final pipeline = Provider.of<StoryPipelineService>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null) return;

    final scene = project.scenes[meta.actIndex]?[meta.sceneIndex];
    if (scene == null) return;

    // Confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF3D2317),
        title: const Text(
          'Rewrite Scene?',
          style: TextStyle(color: Color(0xFFF5E6D3)),
        ),
        content: Text(
          'This will regenerate all prose for "${scene.title}". The page will update automatically when done.',
          style: const TextStyle(color: Color(0xFFD4C4B0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Rewrite',
              style: TextStyle(color: Colors.orange),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRegenerating = true);

    // Clear prose for this scene
    final sId = '${meta.actIndex}-${meta.sceneIndex}';
    final beats = project.beats[sId] ?? [];
    for (int b = 0; b < beats.length; b++) {
      project.prose.remove('$sId-$b');
    }
    await repo.saveProject(project);

    try {
      await pipeline.regenerateSceneProse(
        project,
        meta.actIndex,
        meta.sceneIndex,
      );
      if (mounted) {
        // Force page rebuild
        _pages = null;
        _lastConstraints = null;
        setState(() => _isRegenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${scene.title}" rewritten!'),
            backgroundColor: const Color(0xFF3D2317),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rewrite failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  /// Build the Table of Contents end drawer.
  Widget _buildTocDrawer(bool isTwoPageSpread) {
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null || _pages == null) {
      return const Drawer(child: SizedBox.shrink());
    }

    // Build a map of (actIdx, sceneIdx) -> first page index for that scene
    final Map<String, int> sceneToPage = {};
    for (int i = 0; i < _pages!.length; i++) {
      final p = _pages![i];
      if (p.actIndex != null && p.sceneIndex != null) {
        final key = '${p.actIndex}-${p.sceneIndex}';
        sceneToPage.putIfAbsent(key, () => i);
      }
      if (p.type == _PageType.actTitle) {
        // Find which act this is by matching the title
        for (int a = 0; a < project.acts.length; a++) {
          if (p.title == 'Act ${project.acts[a].number}') {
            sceneToPage.putIfAbsent('act-$a', () => i);
            break;
          }
        }
      }
    }

    return Drawer(
      backgroundColor: const Color(0xFF2C1810),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF5A3A25), width: 1),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    style: const TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF5E6D3),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Table of Contents',
                    style: TextStyle(
                      fontFamily: 'Georgia',
                      fontSize: 12,
                      color: const Color(0xFFF5E6D3).withValues(alpha: 0.5),
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

            // TOC entries
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  // Title page
                  _tocEntry('Title Page', 0, isTwoPageSpread, isTitle: true),

                  for (
                    int actIdx = 0;
                    actIdx < project.acts.length;
                    actIdx++
                  ) ...[
                    const SizedBox(height: 8),
                    // Act header
                    _tocEntry(
                      'Act ${project.acts[actIdx].number}: ${project.acts[actIdx].title}',
                      sceneToPage['act-$actIdx'] ?? 0,
                      isTwoPageSpread,
                      isAct: true,
                    ),
                    // Scenes
                    for (
                      int sceneIdx = 0;
                      sceneIdx < (project.scenes[actIdx]?.length ?? 0);
                      sceneIdx++
                    )
                      _tocEntry(
                        project.scenes[actIdx]![sceneIdx].title,
                        sceneToPage['$actIdx-$sceneIdx'] ?? 0,
                        isTwoPageSpread,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tocEntry(
    String label,
    int pageIndex,
    bool isTwoPageSpread, {
    bool isTitle = false,
    bool isAct = false,
  }) {
    final flipPage = isTwoPageSpread ? pageIndex ~/ 2 : pageIndex;
    final isCurrentPage = _currentPage == flipPage;

    return InkWell(
      onTap: () {
        Navigator.pop(context); // Close drawer
        setState(() => _currentPage = flipPage);
        _flipKey.currentState?.goToPage(flipPage);
      },
      child: Container(
        padding: EdgeInsets.only(
          left: isAct || isTitle ? 20 : 40,
          right: 20,
          top: isAct ? 10 : 6,
          bottom: isAct ? 10 : 6,
        ),
        color: isCurrentPage
            ? const Color(0xFF5A3A25).withValues(alpha: 0.3)
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: isAct ? 14 : 13,
                  fontWeight: isAct || isTitle
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: isCurrentPage
                      ? Colors.amber
                      : isAct || isTitle
                      ? const Color(0xFFF5E6D3)
                      : const Color(0xFFD4C4B0),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${pageIndex + 1}',
              style: TextStyle(
                fontFamily: 'Georgia',
                fontSize: 11,
                color: const Color(0xFFF5E6D3).withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _buildPages(BoxConstraints constraints, bool isTwoPageSpread) {
    if (_pages != null && _lastConstraints == constraints) {
      return; // Already built for this size
    }
    _lastConstraints = constraints;

    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null) {
      _pages = [
        _BookPage(type: _PageType.title, title: 'Story Not Found', body: ''),
      ];
      return;
    }

    // Determine available height and width for text
    final mq = MediaQuery.of(context);

    double availableWidth =
        (isTwoPageSpread ? constraints.maxWidth / 2 : constraints.maxWidth) -
        72;
    if (availableWidth > (600 - 72)) availableWidth = 600 - 72;

    // Subtract external elements from available height:
    // kToolbarHeight (56), SafeArea top/bottom padding, page margins (64), and page padding (96).
    // Adding a 20px extra buffer for text rendering strictness.
    double availableHeight =
        constraints.maxHeight -
        kToolbarHeight -
        mq.padding.top -
        mq.padding.bottom -
        96 // Page padding
        -
        64 // Margin outside book
        -
        24; // Extra safety buffer

    final List<_BookPage> newPages = [];

    // Title page
    newPages.add(
      _BookPage(
        type: _PageType.title,
        title: project.title,
        body: project.concept,
      ),
    );

    final textStyle = const TextStyle(
      fontFamily: 'Georgia',
      fontSize: 15,
      color: Color(0xFF3A2A1A),
      height: 1.75,
      letterSpacing: 0.2,
    );

    // Assemble prose pages
    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      final scenes = project.scenes[actIdx] ?? [];

      // Act title page
      newPages.add(
        _BookPage(
          type: _PageType.actTitle,
          title: 'Act ${act.number}',
          subtitle: act.title,
          body: act.description,
        ),
      );

      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final scene = scenes[sceneIdx];
        final sId = '$actIdx-$sceneIdx';
        final beats = project.beats[sId] ?? [];

        // Collect all prose for this scene
        final proseBuffer = StringBuffer();
        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final bId = '$sId-$beatIdx';
          final prose =
              project.prose[bId]?.final_ ?? project.prose[bId]?.draft ?? '';
          if (prose.isNotEmpty) {
            if (proseBuffer.isNotEmpty) proseBuffer.write('\n\n');
            proseBuffer.write(prose);
          }
        }

        final fullProse = proseBuffer.toString();
        if (fullProse.isEmpty) continue;

        // Header takes up some height (~80px to safely clear the title and margins)
        final headerHeight = 80.0;
        var isFirstPage = true;

        // Split text dynamically
        String remainingText = fullProse;

        while (remainingText.isNotEmpty) {
          final currentAvailableHeight = isFirstPage
              ? availableHeight - headerHeight
              : availableHeight;

          // Find how much text fits
          int startLimit = 0;
          int endLimit = remainingText.length;
          int bestFitLength = endLimit;

          while (startLimit <= endLimit) {
            final mid = (startLimit + endLimit) ~/ 2;
            String testChunk = remainingText.substring(0, mid);

            // Avoid breaking words if possible
            if (mid < remainingText.length &&
                remainingText[mid] != ' ' &&
                remainingText[mid] != '\n') {
              final lastSpace = testChunk.lastIndexOf(RegExp(r'\s'));
              if (lastSpace != -1) {
                testChunk = testChunk.substring(0, lastSpace);
              }
            }

            final tp = TextPainter(
              text: TextSpan(text: testChunk, style: textStyle),
              textDirection: TextDirection.ltr,
            );
            tp.layout(maxWidth: availableWidth);

            if (tp.size.height <= currentAvailableHeight) {
              bestFitLength = testChunk.length;
              startLimit = mid + 1;
            } else {
              endLimit = mid - 1;
            }
          }

          if (bestFitLength == 0) {
            bestFitLength = 1; // Prevent infinite loop on tiny screens
          }

          // Snap strictly to word boundary for aesthetic
          if (bestFitLength < remainingText.length) {
            final testSubstring = remainingText.substring(0, bestFitLength);
            final lastSpace = testSubstring.lastIndexOf(RegExp(r'\s'));
            if (lastSpace > 0 && lastSpace > bestFitLength * 0.5) {
              // Only snap if space isn't too far back
              bestFitLength = lastSpace;
            }
          }

          final chunk = remainingText.substring(0, bestFitLength).trim();
          newPages.add(
            _BookPage(
              type: _PageType.prose,
              title: isFirstPage ? scene.title : '',
              subtitle: isFirstPage ? scene.location : '',
              body: chunk,
              actIndex: actIdx,
              sceneIndex: sceneIdx,
            ),
          );

          remainingText = remainingText.substring(bestFitLength).trimLeft();
          isFirstPage = false;
        }
      }
    }

    // End page
    newPages.add(
      _BookPage(
        type: _PageType.end,
        title: 'The End',
        body: '— ${project.title} —',
      ),
    );

    _pages = newPages;
  }

  /// Assemble the full story text for export.
  String _assembleFullText(StoryProject project) {
    final buffer = StringBuffer();
    buffer.writeln(project.title.toUpperCase());
    buffer.writeln('=' * project.title.length);
    buffer.writeln();
    buffer.writeln(project.concept);
    buffer.writeln();

    for (int actIdx = 0; actIdx < project.acts.length; actIdx++) {
      final act = project.acts[actIdx];
      final scenes = project.scenes[actIdx] ?? [];

      buffer.writeln();
      buffer.writeln('━' * 60);
      buffer.writeln('ACT ${act.number}: ${act.title.toUpperCase()}');
      buffer.writeln('━' * 60);
      buffer.writeln(act.description);
      buffer.writeln();

      for (int sceneIdx = 0; sceneIdx < scenes.length; sceneIdx++) {
        final scene = scenes[sceneIdx];
        final sId = '$actIdx-$sceneIdx';
        final beats = project.beats[sId] ?? [];

        buffer.writeln();
        buffer.writeln('— ${scene.title} —');
        buffer.writeln();

        for (int beatIdx = 0; beatIdx < beats.length; beatIdx++) {
          final bId = '$sId-$beatIdx';
          final prose =
              project.prose[bId]?.final_ ?? project.prose[bId]?.draft ?? '';
          if (prose.isNotEmpty) {
            buffer.writeln(prose);
            buffer.writeln();
          }
        }
      }
    }

    buffer.writeln();
    buffer.writeln('THE END');

    return buffer.toString();
  }

  Future<void> _exportStory() async {
    final repo = Provider.of<StoryRepository>(context, listen: false);
    final project = repo.getById(widget.projectId);
    if (project == null) return;

    final text = _assembleFullText(project);
    final fileName =
        '${project.title.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}.txt';

    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Story',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['txt', 'md'],
      );

      if (outputPath != null) {
        await File(outputPath).writeAsString(text);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('📖 Exported to $outputPath')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  /// Calculates the number of flip views.
  /// On wide screens (2 pages per flip), the count is Math.ceil(_pages.length / 2).
  /// On narrow screens (1 page per flip), it equals _pages.length.
  int _getFlipPageCount() {
    if (_pages == null) return 0;
    final width = MediaQuery.of(context).size.width;
    if (width > 800) {
      return (_pages!.length / 2).ceil();
    }
    return _pages!.length;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTwoPageSpread = width > 800;

    // We wrap everything in LayoutBuilder to measure the screen dynamically.
    // If the window is resized, we must re-calculate pagination.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Trigger page recalculation if size changes significantly
        // For simplicity, we trigger build right here
        _buildPages(constraints, isTwoPageSpread);

        final flipCount = _getFlipPageCount();

        // Handle initial load and window resizing (layout change) seamlessly
        if (_isFirstLoad) {
          final repo = Provider.of<StoryRepository>(context, listen: false);
          final project = repo.getById(widget.projectId);
          if (project != null) {
            _currentPage = isTwoPageSpread
                ? project.lastReadPageIndex ~/ 2
                : project.lastReadPageIndex;
            if (_currentPage >= flipCount) {
              _currentPage = (flipCount - 1).clamp(0, flipCount);
            }
          }
          _isFirstLoad = false;
          _lastIsTwoPageSpread = isTwoPageSpread;
        } else if (_lastIsTwoPageSpread != isTwoPageSpread) {
          // If window was resized and changed spread type, recalculate logical page
          int oldLogicalPage = _lastIsTwoPageSpread
              ? _currentPage * 2
              : _currentPage;
          _currentPage = isTwoPageSpread ? oldLogicalPage ~/ 2 : oldLogicalPage;
          if (_currentPage >= flipCount) {
            _currentPage = (flipCount - 1).clamp(0, flipCount);
          }
          _lastIsTwoPageSpread = isTwoPageSpread;
        }

        // Rebuild the list of flip pages so it's fresh for current screen width
        final List<Widget> flipPages = [];
        for (int i = 0; i < flipCount; i++) {
          if (isTwoPageSpread) {
            final leftIndex = i * 2;
            final rightIndex = leftIndex + 1;
            flipPages.add(
              _buildSpreadView(
                leftPage: leftIndex < _pages!.length
                    ? _pages![leftIndex]
                    : null,
                rightPage: rightIndex < _pages!.length
                    ? _pages![rightIndex]
                    : null,
              ),
            );
          } else {
            flipPages.add(_buildSinglePageContainer(_pages![i]));
          }
        }

        // Determine current logical page to match old UI indexing roughly
        final logicalPageLabel = isTwoPageSpread
            ? '${(_currentPage * 2) + 1}-${((_currentPage * 2) + 2).clamp(1, _pages!.length)}'
            : '${_currentPage + 1}';

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: const Color(0xFF2C1810),
          endDrawer: _buildTocDrawer(isTwoPageSpread),
          appBar: AppBar(
            backgroundColor: const Color(0xFF3D2317),
            foregroundColor: const Color(0xFFF5E6D3),
            elevation: 0,
            title: Text(
              'Page $logicalPageLabel of ${_pages!.length}',
              style: const TextStyle(
                fontFamily: 'Georgia',
                fontSize: 14,
                letterSpacing: 1.5,
              ),
            ),
            centerTitle: true,
            actions: [
              Consumer<TtsService>(
                builder: (context, tts, _) {
                  if (_isReadingAlong) {
                    return Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: _bufferedPageCount > 0
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _bufferedPageCount > 0
                                  ? Colors.green.withValues(alpha: 0.4)
                                  : Colors.orange.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.queue_music,
                                size: 12,
                                color: _bufferedPageCount > 0
                                    ? Colors.greenAccent
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_bufferedPageCount pg',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _bufferedPageCount > 0
                                      ? Colors.greenAccent
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (tts.isGenerating)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                color: Colors.amber,
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        TextButton.icon(
                          onPressed: _stopReadAlong,
                          icon: const Icon(
                            Icons.stop_circle,
                            color: Colors.amber,
                            size: 20,
                          ),
                          label: const Text(
                            'Stop',
                            style: TextStyle(color: Colors.amber, fontSize: 12),
                          ),
                        ),
                      ],
                    );
                  }
                  return TextButton.icon(
                    onPressed: _startReadAlong,
                    icon: const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                    ),
                    label: const Text(
                      'Read to me',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                },
              ),
              const SizedBox(width: 8),
              if (_getCurrentSceneMeta() != null)
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: Colors.orange.withValues(alpha: 0.8),
                  ),
                  tooltip: 'Rewrite this scene',
                  onPressed: _isRegenerating ? null : _regenCurrentScene,
                ),
              IconButton(
                icon: Icon(_isAudioMuted ? Icons.volume_off : Icons.volume_up),
                tooltip: 'Toggle Ambient Audio',
                onPressed: _toggleAudio,
              ),
              IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Export as text file',
                onPressed: _exportStory,
              ),
              IconButton(
                icon: const Icon(Icons.menu_book),
                tooltip: 'Table of Contents',
                onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
              ),
            ],
          ),
          body: Stack(
            children: [
              // Background Book Cover Context
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF1A0E09),
                  child: Center(
                    // Leather backing
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: isTwoPageSpread ? 1200 : 600,
                      ),
                      margin: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(
                          0xFF4A2F1D,
                        ), // Dark leather binding color
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3D Page Flip Widget
              SafeArea(
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: isTwoPageSpread ? 1160 : 580,
                    ),
                    margin: const EdgeInsets.symmetric(
                      vertical: 32,
                      horizontal: 24,
                    ),
                    child: CustomPageFlip(
                      key: _flipKey,
                      initialPage: _currentPage,
                      pages: flipPages,
                      backCover: _buildEndCover(isTwoPageSpread),
                      onPageFlipped: (pageNumber) {
                        setState(() {
                          _currentPage = pageNumber;
                        });

                        // Save reading progress seamlessly
                        final repo = Provider.of<StoryRepository>(
                          context,
                          listen: false,
                        );
                        final project = repo.getById(widget.projectId);
                        if (project != null) {
                          project.lastReadPageIndex = isTwoPageSpread
                              ? pageNumber * 2
                              : pageNumber;
                          repo.saveProject(project);
                        }
                      },
                      onFlipStart: _playPageTurn,
                    ),
                  ),
                ),
              ),

              // Reading progress bar
              Positioned(
                left: 0,
                right: 0,
                bottom: 56,
                child: Center(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: isTwoPageSpread ? 1160 : 580,
                    ),
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: flipCount > 1
                            ? _currentPage / (flipCount - 1)
                            : 1.0,
                        backgroundColor: const Color(
                          0xFF5A3A25,
                        ).withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.amber.withValues(alpha: 0.5),
                        ),
                        minHeight: 3,
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom page indicator with navigation buttons
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3D2317).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _flipKey.currentState?.previousPage(),
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.chevron_left,
                              color: Color(0xFFF5E6D3),
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Page $logicalPageLabel / ${_pages!.length}',
                          style: const TextStyle(
                            color: Color(0xFFF5E6D3),
                            fontFamily: 'Georgia',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: () => _flipKey.currentState?.nextPage(),
                          borderRadius: BorderRadius.circular(16),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.chevron_right,
                              color: Color(0xFFF5E6D3),
                              size: 28,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEndCover(bool isTwoPage) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8DCC8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Center(
        child: Text(
          '⸻ ✦ ⸻\nClosed',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 24,
            color: Color(0xFF8B7355),
          ),
        ),
      ),
    );
  }

  Widget _buildSpreadView({_BookPage? leftPage, _BookPage? rightPage}) {
    return Row(
      children: [
        Expanded(
          child: _buildSinglePageContainer(leftPage, isLeftSpread: true),
        ),
        Expanded(
          child: _buildSinglePageContainer(rightPage, isRightSpread: true),
        ),
      ],
    );
  }

  Widget _buildSinglePageContainer(
    _BookPage? page, {
    bool isLeftSpread = false,
    bool isRightSpread = false,
  }) {
    if (page == null) {
      // Empty blank page at end of a right-hand spread
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5ECD7),
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(isRightSpread ? 0 : 4),
            right: Radius.circular(isLeftSpread ? 0 : 4),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        // Paper texture effect
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isLeftSpread
              ? const [Color(0xFFF0E5CC), Color(0xFFFAF3E8), Color(0xFFF5ECD7)]
              : isRightSpread
              ? const [Color(0xFFF5ECD7), Color(0xFFFAF3E8), Color(0xFFF0E5CC)]
              : const [Color(0xFFF0E5CC), Color(0xFFFAF3E8), Color(0xFFF0E5CC)],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(isRightSpread ? 0 : 4),
          right: Radius.circular(isLeftSpread ? 0 : 4),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(isRightSpread ? 0 : 4),
          right: Radius.circular(isLeftSpread ? 0 : 4),
        ),
        child: Stack(
          children: [
            // Center binding shadow
            if (isLeftSpread)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 40,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            if (isRightSpread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 40,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

            // Subtle page edge effect (left side "binding") for single page
            if (!isLeftSpread && !isRightSpread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 24,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.brown.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

            // Content
            Container(
              alignment: page.type == _PageType.prose
                  ? Alignment.topLeft
                  : Alignment.center,
              padding: EdgeInsets.fromLTRB(
                isRightSpread ? 40 : 32, // More padding near binding
                48,
                isLeftSpread ? 40 : 32,
                48,
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: _buildPageContent(page),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageContent(_BookPage page) {
    switch (page.type) {
      case _PageType.title:
        return _buildTitlePage(page);
      case _PageType.actTitle:
        return _buildActTitlePage(page);
      case _PageType.prose:
        return _buildProsePage(page);
      case _PageType.end:
        return _buildEndPage(page);
    }
  }

  Widget _buildTitlePage(_BookPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Decorative flourish
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(0xFF8B7355).withValues(alpha: 0.5),
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          page.title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C1810),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 60,
          height: 1,
          color: const Color(0xFF8B7355).withValues(alpha: 0.4),
        ),
        const SizedBox(height: 16),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 14,
            fontStyle: FontStyle.italic,
            color: Color(0xFF5A4A3A),
            height: 1.6,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(0xFF8B7355).withValues(alpha: 0.5),
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 48),
        const Text(
          'A Porch Story',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 12,
            color: Color(0xFF8B7355),
            letterSpacing: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildActTitlePage(_BookPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          page.title,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 16,
            letterSpacing: 6,
            color: Color(0xFF8B7355),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 40,
          height: 1,
          color: const Color(0xFF8B7355).withValues(alpha: 0.4),
        ),
        const SizedBox(height: 16),
        Text(
          page.subtitle ?? '',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF2C1810),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            page.body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: Color(0xFF5A4A3A),
              height: 1.6,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProsePage(_BookPage page) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scene heading (only on first page of scene)
        if (page.title.isNotEmpty) ...[
          Text(
            page.title,
            style: const TextStyle(
              fontFamily: 'Georgia',
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C1810),
              height: 1.4,
            ),
          ),
          if (page.subtitle != null && page.subtitle!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                page.subtitle!,
                style: const TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF8B7355),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Container(
            width: 40,
            height: 1,
            color: const Color(0xFF8B7355).withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
        ],
        // Prose text
        Text(
          page.body,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 15,
            color: Color(0xFF3A2A1A),
            height: 1.75,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildEndPage(_BookPage page) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(0xFF8B7355).withValues(alpha: 0.5),
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'The End',
          style: TextStyle(
            fontFamily: 'Georgia',
            fontSize: 28,
            fontStyle: FontStyle.italic,
            color: Color(0xFF2C1810),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          page.body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Georgia',
            fontSize: 14,
            color: Color(0xFF8B7355),
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 48),
        Text(
          '⸻ ✦ ⸻',
          style: TextStyle(
            color: const Color(0xFF8B7355).withValues(alpha: 0.5),
            fontSize: 20,
            letterSpacing: 8,
          ),
        ),
      ],
    );
  }
}

// ── Page model ──

enum _PageType { title, actTitle, prose, end }

class _BookPage {
  final _PageType type;
  final String title;
  final String? subtitle;
  final String body;
  final int? actIndex;
  final int? sceneIndex;

  const _BookPage({
    required this.type,
    required this.title,
    this.subtitle,
    required this.body,
    this.actIndex,
    this.sceneIndex,
  });
}
