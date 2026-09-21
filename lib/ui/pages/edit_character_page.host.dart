// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tab host: token badge, avatar resolve, lore CRUD/import, and the
// scaffold TabBar. Field bag and init stay on the page shell.

part of 'edit_character_page.dart';

extension _EditCharacterPageHost on _EditCharacterPageState {
  void _updateTokenCount() {
    int totalChars =
        _nameController.text.length +
        _descriptionController.text.length +
        _personalityController.text.length +
        _scenarioController.text.length +
        _firstMessageController.text.length +
        _mesExampleController.text.length +
        _systemPromptController.text.length +
        _postHistoryController.text.length;
    for (final c in _altGreetingControllers) {
      totalChars += c.text.length;
    }
    _tokenNotifier.value = (totalChars / 4).ceil();
  }

  /// Card face for this page: the ★ starred gallery look when set, else the
  /// library portrait — same resolution as the home grid / export cover
  /// (issue #171: used to read raw `imagePath` only, so Add avatar + ★ left
  /// this page stuck on "No avatar" while chat already showed the look).
  ///
  /// Cost: once per Details rebuild via the repo's cover cache (not a chat
  /// bubble hot path). Prefer this over a raw existsSync on imagePath.
  /// Falls back to raw `imagePath` when CharacterRepository is not above this
  /// widget (widget goldens / rare embeds that only provide StorageService).
  File? get _avatarFile {
    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final cover = repo.coverImageFileFor(widget.character);
      if (cover != null) return cover;
    } on ProviderNotFoundException {
      // Fall through to imagePath.
    }
    final img = widget.character.imagePath;
    if (img == null || img.isEmpty) return null;
    if (p.isAbsolute(img)) return File(img);
    try {
      final storage = Provider.of<StorageService>(context, listen: false);
      return File(p.join(storage.charactersDir.path, img));
    } on ProviderNotFoundException {
      return File(img);
    }
  }

  Future<void> _addLoreEntry() async {
    final result = await showLorebookEntryDialog(context: context);
    if (result != null) {
      rebuildState(() => _loreEntries.add(result));
    }
  }

  void _removeLoreEntry(int index) {
    rebuildState(() {
      _loreEntries.removeAt(index);
    });
  }

  Future<void> _editLoreEntry(int index) async {
    final entry = _loreEntries[index];
    final result = await showLorebookEntryDialog(
      context: context,
      existing: entry,
      showEnabled: true,
    );
    if (result != null) {
      rebuildState(() => _loreEntries[index] = result);
    }
  }

  Future<void> _importLoreFromCharacter() async {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final entries = await showImportCharacterLoreDialog(
      context: context,
      characters: repo.characters,
      excludeCharacterName: widget.character.name,
    );
    if (entries == null || entries.isEmpty) return;
    rebuildState(() {
      _loreEntries.addAll(entries);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${entries.length} entries from character.'),
        ),
      );
    }
  }

  Future<void> _importLorebookJson() async {
    final result = await PickerPrefs.pickFiles(
      category: PickerPrefs.catImport,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;

    try {
      final content = utf8.decode(await result.files.single.readAsBytes());
      final dynamic jsonData = jsonDecode(content);

      if (jsonData is! Map<String, dynamic>) {
        throw FormatException('Invalid JSON format: expected a JSON object');
      }

      final Map<String, dynamic> json = jsonData;

      if (json['entries'] == null && json['lorebook'] == null) {
        throw FormatException(
          'Invalid lorebook file: missing "entries" or "lorebook" field. '
          'Supported formats: SillyTavern, Chub.ai, Front Porch.',
        );
      }

      final lorebook = Lorebook.fromJson(json);

      if (lorebook.entries.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No entries found in file.')),
          );
        }
        return;
      }

      rebuildState(() {
        _loreEntries.addAll(lorebook.entries);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Imported ${lorebook.entries.length} entries.'),
          ),
        );
      }
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid file format: ${e.message}')),
        );
      }
    } on Exception catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import failed. Please try again.')),
        );
      }
    }
  }

  Widget _buildHost(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.cardOf(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppColors.iconSecondary(context)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.edit_note,
              color: AppColors.formMasterAccent,
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Edit ${widget.character.name}',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              onPressed: _saveCharacter,
              icon: Icon(
                widget.popWithCardOnSave
                    ? Icons.arrow_forward_rounded
                    : Icons.save_outlined,
                size: 18,
              ),
              label: Text(widget.saveLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.formMasterAccent,
                foregroundColor: AppColors.onChaosAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.formMasterAccent,
          unselectedLabelColor: AppColors.textTertiary(context),
          indicatorColor: AppColors.formMasterAccent,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.person_outline, size: 18), text: 'Details'),
            Tab(
              icon: Icon(Icons.chat_bubble_outline, size: 18),
              text: 'Dialogue',
            ),
            Tab(
              icon: Icon(Icons.menu_book_outlined, size: 18),
              text: 'Lorebook',
            ),
            Tab(icon: Icon(Icons.public, size: 18), text: 'Worlds'),
          ],
        ),
      ),
      body: Stack(
        children: [
          TabBarView(
            controller: _tabController,
            children: [
              _buildDetailsTab(),
              _buildDialogueTab(),
              _buildLorebookTab(),
              _buildWorldsTab(),
            ],
          ),
          Positioned(
            right: 24,
            bottom: 24,
            child: ValueListenableBuilder<int>(
              valueListenable: _tokenNotifier,
              builder: (context, tokens, child) => _buildTokenBadge(tokens),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokenBadge(int estimatedTokens) {
    final color = estimatedTokens > 4000
        ? AppColors.negativeAccentOf(context)
        : estimatedTokens > 2000
        ? AppColors.porchTerracottaOf(context)
        : AppColors.formMasterAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.token, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '~$estimatedTokens tokens',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
