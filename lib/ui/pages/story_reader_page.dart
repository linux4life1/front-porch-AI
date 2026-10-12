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
import 'package:audioplayers/audioplayers.dart';
import 'package:front_porch_ai/ui/widgets/custom_page_flip.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/story_reader/story_reader.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// A book-like reader for completed Porch Stories with paper aesthetic
/// and page-by-page navigation, or a continuous scroll with chapter
/// headings (the story remembers which).
class StoryReaderPage extends StatefulWidget {
  final String projectId;

  /// Inside the studio (sketch P): no back arrow of its own; the studio
  /// header surrounds it and ☰ folds the sidebar away.
  final bool embedded;
  final VoidCallback? onToggleSidebar;

  const StoryReaderPage({
    super.key,
    required this.projectId,
    this.embedded = false,
    this.onToggleSidebar,
  });

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  final _flipKey = GlobalKey<CustomPageFlipState>();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _currentPage = 0;
  List<BookPage>? _pages; // Null when not yet calculated
  BoxConstraints? _lastConstraints;
  bool _isFirstLoad = true;
  bool _lastIsTwoPageSpread = false;

  late AudioPlayer _ambientPlayer;
  late AudioPlayer _sfxPlayer;
  bool _isAudioPlaying = true;
  bool _isAudioMuted = true; // explicitly muted by default per user request

  final _readAlong = StoryReadAlong();

  // Scroll mode.
  final _scroll = StoryScrollTracker();
  int _scrollChapter = 0;
  bool _hudHidden = false;
  bool _scrollRestored = false;

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
    _readAlong.isReading = false;
    // ensure TTS stops on exit
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        Provider.of<TtsService>(context, listen: false).stop();
      } catch (_) {}
    });
    _ambientPlayer.dispose();
    _sfxPlayer.dispose();
    _readAlong.dispose();
    _scroll.dispose();
    super.dispose();
  }

  StoryRepository get _repo =>
      Provider.of<StoryRepository>(context, listen: false);

  void _buildPages(BoxConstraints constraints, bool isTwoPageSpread) {
    if (_pages != null && _lastConstraints == constraints) {
      return; // Already built for this size
    }
    _lastConstraints = constraints;
    _pages = paginateStory(
      project: _repo.getById(widget.projectId),
      constraints: constraints,
      isTwoPageSpread: isTwoPageSpread,
      viewPadding: MediaQuery.of(context).padding,
    );
  }

  int _getFlipPageCount() {
    if (_pages == null) return 0;
    return flipPageCountFor(_pages!, MediaQuery.of(context).size.width);
  }

  /// Get the text content for a given flip-page index.
  String _getPageText(int flipPage) {
    if (_pages == null) return '';
    final isTwoPageSpread = MediaQuery.of(context).size.width > 800;
    return flipPageText(_pages!, flipPage, isTwoPageSpread);
  }

  Future<void> _startReadAlong() async {
    if (_readAlong.isReading || _pages == null) return;
    final tts = Provider.of<TtsService>(context, listen: false);
    final storage = Provider.of<StorageService>(context, listen: false);
    if (!storage.ttsSettings.ttsEnabled) {
      await showVoiceOffDialog(context);
      return;
    }
    setState(() => _readAlong.isReading = true);

    final project = _repo.getById(widget.projectId);
    final cast = project?.cast ?? [];

    await _readAlong.run(
      tts: tts,
      cast: cast,
      flipCount: _getFlipPageCount(),
      currentPage: () => _currentPage,
      pageText: _getPageText,
      advancePage: () {
        // In scroll mode there is no flip widget to advance the page.
        if (_flipKey.currentState != null) {
          _flipKey.currentState!.nextPage();
        } else {
          setState(() => _currentPage++);
        }
      },
      isMounted: () => mounted,
      update: setState,
    );
  }

  void _stopReadAlong() {
    _readAlong.stop();
    Provider.of<TtsService>(context, listen: false).stop();
    setState(() {});
  }

  Future<void> _exportStory() async {
    final project = _repo.getById(widget.projectId);
    if (project == null) return;
    await exportStoryText(context, project);
  }

  Future<void> _setReaderMode(StoryProject project, String mode) async {
    project.readerMode = mode;
    await _repo.saveProject(project);
    setState(() => _hudHidden = false);
  }

  void _saveScroll(StoryProject project) {
    final recorded = _scroll.recordProgress(project, () {
      if (!mounted) return;
      _repo.saveProject(project);
    });
    if (!recorded) return;
    _updateVisibleChapter();
  }

  void _updateVisibleChapter() {
    final visible = _scroll.visibleChapter();
    if (visible != _scrollChapter) setState(() => _scrollChapter = visible);
  }

  /// Read aloud from the visible chapter: point the page-based read-along
  /// at that chapter's first page and let it run.
  void _readAloudVisibleChapter(StoryProject project) {
    if (_readAlong.isReading) {
      _stopReadAlong();
      return;
    }
    final chapters = storyChapters(project);
    if (_pages == null || chapters.isEmpty) return;
    final ref = chapters[_scrollChapter.clamp(0, chapters.length - 1)];
    final pageIdx = _pages!.indexWhere(
      (p) => p.actIndex == ref.act && p.sceneIndex == ref.index,
    );
    if (pageIdx == -1) return;
    final isTwoPageSpread = MediaQuery.of(context).size.width > 800;
    setState(() => _currentPage = isTwoPageSpread ? pageIdx ~/ 2 : pageIdx);
    _startReadAlong();
  }

  void _onTocSelect(int pageIndex, int flipPage) {
    Navigator.pop(context); // Close drawer
    // Scroll mode has no flip widget: jump to the page's chapter.
    if (_flipKey.currentState == null) {
      final page = _pages![pageIndex.clamp(0, _pages!.length - 1)];
      final act = page.actIndex;
      final scene = page.sceneIndex;
      if (act != null && scene != null) {
        final project = _repo.getById(widget.projectId);
        if (project != null) {
          final chapters = storyChapters(project);
          final i = chapters.indexWhere(
            (c) => c.act == act && c.index == scene,
          );
          if (i >= 0) _scroll.jumpToChapter(i);
        }
      }
      return;
    }
    setState(() => _currentPage = flipPage);
    _flipKey.currentState?.goToPage(flipPage);
  }

  void _onPageFlipped(int pageNumber, bool isTwoPageSpread) {
    setState(() {
      _currentPage = pageNumber;
    });

    // Save reading progress seamlessly
    final repo = _repo;
    final project = repo.getById(widget.projectId);
    if (project != null) {
      project.lastReadPageIndex = isTwoPageSpread ? pageNumber * 2 : pageNumber;
      repo.saveProject(project);
    }
  }

  Widget _tocDrawer(StoryProject? project, bool isTwoPageSpread) =>
      StoryTocDrawer(
        project: project,
        pages: _pages,
        isTwoPageSpread: isTwoPageSpread,
        currentPage: _currentPage,
        onSelect: _onTocSelect,
      );

  PreferredSizeWidget _studioBar(StoryProject project, String where) =>
      StoryReaderBar(
        project: project,
        where: where,
        embedded: widget.embedded,
        onToggleSidebar: widget.onToggleSidebar,
        onReaderModeSelected: (m) => _setReaderMode(project, m),
        onOpenContents: () => _scaffoldKey.currentState?.openEndDrawer(),
        isAudioMuted: _isAudioMuted,
        onToggleAudio: _toggleAudio,
        onExport: _exportStory,
        isReadingAlong: _readAlong.isReading,
        bufferedPageCount: _readAlong.bufferedPageCount,
        onReadAloud: project.readerMode == 'scroll'
            ? () => _readAloudVisibleChapter(project)
            : _startReadAlong,
        onStopReadAlong: _stopReadAlong,
      );

  Widget _buildScrollMode(StoryProject project) {
    final chapters = storyChapters(project);
    _scroll.syncChapterCount(chapters.length);
    if (!_scrollRestored) {
      _scrollRestored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final controller = _scroll.controller;
        if (!mounted || !controller.hasClients) return;
        final max = controller.position.maxScrollExtent;
        controller.jumpTo(project.readerScroll * max);
        _updateVisibleChapter();
      });
    }
    final chapter = chapters.isEmpty
        ? null
        : chapters[_scrollChapter.clamp(0, chapters.length - 1)];
    final percent = _scroll.percent;

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _tocDrawer(project, MediaQuery.of(context).size.width > 800),
      backgroundColor: StudioColors.bgOf(context),
      appBar: _hudHidden
          ? null
          : _studioBar(
              project,
              chapter == null ? '' : 'Ch. ${_scrollChapter + 1} · $percent%',
            ),
      body: StoryScrollBody(
        project: project,
        chapters: chapters,
        controller: _scroll.controller,
        chapterKeys: _scroll.chapterKeys,
        scrollChapter: _scrollChapter,
        hudHidden: _hudHidden,
        onToggleHud: () => setState(() => _hudHidden = !_hudHidden),
        onScrolled: () => _saveScroll(project),
        onJumpToChapter: _scroll.jumpToChapter,
      ),
    );
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

        final scrollProject = _repo.getById(widget.projectId);
        if (scrollProject != null && scrollProject.readerMode == 'scroll') {
          return _buildScrollMode(scrollProject);
        }

        final flipCount = _getFlipPageCount();

        // Handle initial load and window resizing (layout change) seamlessly
        if (_isFirstLoad) {
          final project = _repo.getById(widget.projectId);
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

        // Determine current logical page to match old UI indexing roughly
        final logicalPageLabel = isTwoPageSpread
            ? '${(_currentPage * 2) + 1}-${((_currentPage * 2) + 2).clamp(1, _pages!.length)}'
            : '${_currentPage + 1}';

        return BookReaderView(
          scaffoldKey: _scaffoldKey,
          flipKey: _flipKey,
          endDrawer: _tocDrawer(scrollProject, isTwoPageSpread),
          appBar: scrollProject == null
              ? null
              : _studioBar(
                  scrollProject,
                  'Page $logicalPageLabel of ${_pages!.length}',
                ),
          pages: _pages!,
          isTwoPageSpread: isTwoPageSpread,
          flipCount: flipCount,
          currentPage: _currentPage,
          pageLabel: logicalPageLabel,
          onPageFlipped: (pageNumber) =>
              _onPageFlipped(pageNumber, isTwoPageSpread),
          onFlipStart: _playPageTurn,
        );
      },
    );
  }
}
