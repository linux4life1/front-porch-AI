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

part of 'story_reader_page.dart';

/// Scroll mode: one continuous column with a heading per chapter (a scene
/// with prose), resuming where the reader left off. A tap in the middle
/// hides the controls; the chapter buttons and Read aloud sit at the bottom.
extension _StoryReaderScroll on _StoryReaderPageState {
  static const _ordinals = [
    'ONE',
    'TWO',
    'THREE',
    'FOUR',
    'FIVE',
    'SIX',
    'SEVEN',
    'EIGHT',
    'NINE',
    'TEN',
    'ELEVEN',
    'TWELVE',
    'THIRTEEN',
    'FOURTEEN',
    'FIFTEEN',
    'SIXTEEN',
    'SEVENTEEN',
    'EIGHTEEN',
    'NINETEEN',
    'TWENTY',
  ];

  static String _chapterWord(int n) =>
      n <= _ordinals.length ? _ordinals[n - 1] : '$n';

  /// Scenes with prose, in story order.
  List<SceneRef> _chapters(StoryProject project) => [
    for (final ref in project.orderedScenes)
      if (project.sceneHasProse(ref.act, ref.index)) ref,
  ];

  Future<void> _setReaderMode(StoryProject project, String mode) async {
    project.readerMode = mode;
    await Provider.of<StoryRepository>(
      context,
      listen: false,
    ).saveProject(project);
    rebuildState(() => _hudHidden = false);
  }

  void _saveScroll(StoryProject project) {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    project.readerScroll = max <= 0
        ? 0
        : (_scrollController.offset / max).clamp(0.0, 1.0);
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      Provider.of<StoryRepository>(context, listen: false).saveProject(project);
    });
    _updateVisibleChapter();
  }

  /// The chapter whose heading is nearest above the top of the view.
  void _updateVisibleChapter() {
    var visible = 0;
    for (var i = 0; i < _chapterKeys.length; i++) {
      final box = _chapterKeys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= 160) visible = i;
    }
    if (visible != _scrollChapter) rebuildState(() => _scrollChapter = visible);
  }

  void _jumpToChapter(int index) {
    if (index < 0 || index >= _chapterKeys.length) return;
    final ctx = _chapterKeys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      alignment: 0.02,
    );
  }

  /// Read aloud from the visible chapter: point the page-based read-along
  /// at that chapter's first page and let it run.
  void _readAloudVisibleChapter(StoryProject project) {
    if (_isReadingAlong) {
      _stopReadAlong();
      return;
    }
    final chapters = _chapters(project);
    if (_pages == null || chapters.isEmpty) return;
    final ref = chapters[_scrollChapter.clamp(0, chapters.length - 1)];
    final pageIdx = _pages!.indexWhere(
      (p) => p.actIndex == ref.act && p.sceneIndex == ref.index,
    );
    if (pageIdx == -1) return;
    final isTwoPageSpread = MediaQuery.of(context).size.width > 800;
    rebuildState(() => _currentPage = isTwoPageSpread ? pageIdx ~/ 2 : pageIdx);
    _startReadAlong();
  }

  Widget _buildScrollMode(StoryProject project) {
    final chapters = _chapters(project);
    if (_chapterKeys.length != chapters.length) {
      _chapterKeys
        ..clear()
        ..addAll(List.generate(chapters.length, (_) => GlobalKey()));
    }
    if (!_scrollRestored) {
      _scrollRestored = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final max = _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(project.readerScroll * max);
        _updateVisibleChapter();
      });
    }
    final paper = AppColors.resolve(
      context,
      const Color(0xFFE8DDCF),
      AppColors.textPrimary(context),
    );
    final muted = AppColors.porchHoneyOf(context);
    final chapter = chapters.isEmpty
        ? null
        : chapters[_scrollChapter.clamp(0, chapters.length - 1)];
    final percent =
        _scrollController.hasClients &&
            _scrollController.position.maxScrollExtent > 0
        ? (_scrollController.offset /
                  _scrollController.position.maxScrollExtent *
                  100)
              .round()
        : 0;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.backgroundOf(context),
      endDrawer: _buildTocDrawer(MediaQuery.of(context).size.width > 800),
      appBar: _hudHidden
          ? null
          : AppBar(
              automaticallyImplyLeading: !widget.embedded,
              backgroundColor: AppColors.surfaceOf(context),
              foregroundColor: AppColors.textPrimary(context),
              elevation: 0,
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    project.title,
                    style: const TextStyle(fontFamily: 'Georgia', fontSize: 14),
                  ),
                  const SizedBox(width: 12),
                  _modeToggle(project),
                ],
              ),
              centerTitle: true,
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Center(
                    child: Text(
                      chapter == null
                          ? ''
                          : 'Ch. ${_scrollChapter + 1} · $percent%',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
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
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx > w * 0.3 && d.globalPosition.dx < w * 0.7) {
            rebuildState(() => _hudHidden = !_hudHidden);
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollEndNotification || n is ScrollUpdateNotification) {
              _saveScroll(project);
            }
            return false;
          },
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
                      itemCount: chapters.length,
                      itemBuilder: (context, i) {
                        final ref = chapters[i];
                        final text = project.sceneText(ref.act, ref.index);
                        return Column(
                          key: _chapterKeys[i],
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (i > 0) const SizedBox(height: 48),
                            Text(
                              'CHAPTER ${_chapterWord(i + 1)}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: muted,
                                fontFamily: 'Georgia',
                                fontSize: 12,
                                letterSpacing: 2.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ref.scene.title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: paper,
                                fontFamily: 'Georgia',
                                fontSize: 22,
                              ),
                            ),
                            const SizedBox(height: 18),
                            for (final para in text.split(RegExp(r'\n\s*\n')))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: SelectableText(
                                  para.trim(),
                                  style: TextStyle(
                                    color: paper,
                                    fontFamily: 'Georgia',
                                    fontSize: 15.5,
                                    height: 1.7,
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (!_hudHidden)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  color: AppColors.surfaceOf(context).withValues(alpha: 0.9),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _scrollChapter > 0
                            ? () => _jumpToChapter(_scrollChapter - 1)
                            : null,
                        child: Text('◀ Ch. $_scrollChapter'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: chapters.isEmpty
                            ? null
                            : () => _readAloudVisibleChapter(project),
                        icon: Icon(
                          _isReadingAlong ? Icons.stop : Icons.play_arrow,
                          size: 16,
                        ),
                        label: Text(_isReadingAlong ? 'Stop' : 'Read aloud'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textPrimary(context),
                          side: BorderSide(color: AppColors.borderOf(context)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _scrollChapter < chapters.length - 1
                            ? () => _jumpToChapter(_scrollChapter + 1)
                            : null,
                        child: Text('Ch. ${_scrollChapter + 2} ▶'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _modeToggle(StoryProject project) => StorySegmented(
    options: const {'book': 'Book', 'scroll': 'Scroll'},
    selected: project.readerMode,
    onSelect: (m) => _setReaderMode(project, m),
  );
}
