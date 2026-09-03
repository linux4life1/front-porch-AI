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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:front_porch_ai/ui/widgets/custom_page_flip.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story_narration_service.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'story_reader_page.readalong.dart';
part 'story_reader_page.actions.dart';
part 'story_reader_page.toc.dart';
part 'story_reader_page.pagination.dart';
part 'story_reader_page.pages.dart';

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

  // Read-along audio player (separate from ambient). Relocated here from its
  // former mid-file position — the read-along playback logic now lives in an
  // `extension` in story_reader_page.readalong.dart, and extensions cannot
  // hold fields, so every field the extracted methods touch must live on the
  // State itself.
  AudioPlayer? _readAlongPlayer;

  // Scene regeneration flag — relocated here for the same reason;
  // _regenCurrentScene now lives in the extension in
  // story_reader_page.actions.dart.
  bool _isRegenerating = false;

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

  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`story_reader_page.*.dart`), which hold read-along playback, scene
  /// regeneration, and the TOC drawer but can't call a State's protected
  /// members directly.
  void rebuildState(VoidCallback fn) => setState(fn);

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
          backgroundColor: AppColors.backgroundOf(context),
          endDrawer: _buildTocDrawer(isTwoPageSpread),
          appBar: AppBar(
            backgroundColor: AppColors.surfaceOf(context),
            foregroundColor: AppColors.textPrimary(context),
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
              _buildReadAlongAction(),
              const SizedBox(width: 8),
              if (_getCurrentSceneMeta() != null)
                IconButton(
                  icon: Icon(
                    Icons.refresh,
                    color: AppColors.porchAmberOf(
                      context,
                    ).withValues(alpha: 0.8),
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
                  color: AppColors.surfaceOf(context),
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
                        // Dark leather binding color — theme-keep: book prop
                        // (the reader is a book prop; its cover stays leather
                        // brown in every app theme, light or dark).
                        color: const Color(0xFF4A2F1D),
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            // theme-keep: book prop (a physical drop shadow
                            // stays black regardless of app theme).
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
                        backgroundColor: AppColors.surfaceContainerOf(
                          context,
                        ).withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.porchAmberOf(
                            context,
                          ).withValues(alpha: 0.5),
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
                      color: AppColors.surfaceOf(
                        context,
                      ).withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          onTap: () => _flipKey.currentState?.previousPage(),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.chevron_left,
                              color: AppColors.textPrimary(context),
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Page $logicalPageLabel / ${_pages!.length}',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontFamily: 'Georgia',
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 16),
                        InkWell(
                          onTap: () => _flipKey.currentState?.nextPage(),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.chevron_right,
                              color: AppColors.textPrimary(context),
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
}
