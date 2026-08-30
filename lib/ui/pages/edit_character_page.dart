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
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/chat.dart'
    show Pockets, BirthdayMath;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/greeting_seed_form.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/utils/utils.dart';

part 'edit_character_page.realism_section.dart';
part 'edit_character_page.save.dart';
part 'edit_character_page.tab_worlds.dart';
part 'edit_character_page.tabs_core.dart';
part 'edit_character_page.tabs_lore.dart';

// ═══════════════════════════════════════════════════════════════
//  DESIGN TOKENS — Slate / Indigo dark theme
// ═══════════════════════════════════════════════════════════════

// Theme-aware surfaces (dark values identical to the old hardcoded navy
// tokens, so dark mode is unchanged; light mode finally gets light).
const _borderFocus = AppColors.formMasterAccent;

class EditCharacterPage extends StatefulWidget {
  final CharacterCard character;

  /// Label for the save action (default "Save"). The Stoop update flow passes
  /// "Next" so this editor reads as the first step of publishing an update.
  final String saveLabel;

  /// When true, a successful save pops this page returning the saved
  /// [CharacterCard] (instead of showing the "updated" snackbar and popping with
  /// no result), so a caller can continue a flow with the freshly-saved card.
  final bool popWithCardOnSave;

  /// When set, save persistence is DELEGATED to this callback instead of writing
  /// to the library (`CharacterRepository.updateCharacter`). Used to edit a group
  /// member: the field updates + PNG save still run on the card, but the row is
  /// written to the group (via the caller) so nothing backflows to the library.
  final Future<void> Function(CharacterCard saved)? onSaveOverride;

  /// Show the Realism/Needs section (default true). Hidden for group members,
  /// whose realism/needs are group state edited in Group Settings.
  final bool showRealismTab;

  /// Allow changing the avatar (default true). Disabled for group members in this
  /// pass, since a member's avatar lives at a private group path.
  final bool allowAvatarChange;

  /// Called after a successful save with the freshly-saved card — a
  /// persistence-agnostic notification (fires on the library path AND the
  /// [onSaveOverride] path, though no current caller passes both). The
  /// in-chat editor (this page in a Dialog, chat_page's "Edit Character")
  /// uses it for ChatService.refreshActiveCharacterCard — the light,
  /// group-safe live refresh that replaced the deleted EditCharacterDialog's
  /// per-control persistence dance.
  final Future<void> Function(CharacterCard saved)? onSaved;

  const EditCharacterPage({
    super.key,
    required this.character,
    this.saveLabel = 'Save',
    this.popWithCardOnSave = false,
    this.onSaveOverride,
    this.showRealismTab = true,
    this.allowAvatarChange = true,
    this.onSaved,
  });

  @override
  State<EditCharacterPage> createState() => _EditCharacterPageState();
}

class _EditCharacterPageState extends State<EditCharacterPage>
    with SingleTickerProviderStateMixin {
  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`edit_character_page.*.dart`). Same bridge as settings_page/chat_page.
  void rebuildState(VoidCallback fn) => setState(fn);

  late TextEditingController _nameController;
  late StyledTextController _descriptionController;
  late StyledTextController _personalityController;
  late StyledTextController _scenarioController;
  late StyledTextController _firstMessageController;
  late StyledTextController _mesExampleController;
  late StyledTextController _systemPromptController;
  late StyledTextController _postHistoryController;

  late TabController _tabController;
  List<LorebookEntry> _loreEntries = [];
  List<String> _selectedWorldNames = [];
  List<String> _initialWorldNames = const [];
  List<StyledTextController> _altGreetingControllers = [];
  List<GreetingRealismSeed?> _altGreetingSeeds = [];
  List<String> _tags = [];

  /// The character's own TTS voice id; '' means "follow the global
  /// Settings voice". Editable in the Details tab's Voice card.
  String _ttsVoice = '';
  final _tagController = TextEditingController();

  /// Long-term ambitions (Living Time §6), one per line. Identity — travels
  /// with the card; per-chat progress lives in the Journal.
  // Ambitions are a LIST, not newline-encoded text (see ChipListEditor).
  List<String> _ambitions = const [];
  List<String> _planLines = const [];
  String _occupation = '';
  String _occupationBrief = '';
  String _hours = '';
  List<int>? _workDays;
  String _birthday = '';

  /// Likes & Dislikes and the 18+ pair — card-authored identity, same shape
  /// and same chip editor as [_ambitions].
  List<String> _likes = const [];
  List<String> _dislikes = const [];
  List<String> _intimateInto = const [];
  List<String> _intimateNotInto = const [];

  /// Starting Pockets & Wardrobe, held as the chip text the user sees
  /// (`sundress (rain-soaked)`) rather than as parsed items. The card stores a
  /// map of `{name, state}`; [Pockets] owns both directions of that conversion
  /// so the editor never has to hold two representations at once.
  List<String> _worn = const [];
  List<String> _carrying = const [];
  final ValueNotifier<int> _tokenNotifier = ValueNotifier<int>(0);

  // ── Realism Engine state ──
  bool _realismEnabled = false;
  bool _realismSettingsModified = false;
  String _realismTimeOfDay = 'morning';
  int _realismDayCount = 1;
  // Story Calendar authoring (story-calendar.md §3a): null start date =
  // "the day the chat starts"; null time = period default.
  String? _realismStoryStartDate;
  String? _realismStoryStartTime;
  int _realismShortTermBond = 0;
  int _realismLongTermBond = 0;
  int _realismTrustLevel = 0;
  String _realismEmotion = '';
  String _realismEmotionIntensity = 'mild';
  bool _realismNsfwCooldown = false;
  bool _realismPassageOfTime = true;
  bool _realismChaosMode = false;
  bool _realismNeedsSim = false;
  bool _realismEnjoysLowHygiene = false;

  /// Read-and-write-back only — no editor writes this any more (Ambitions
  /// replaced the "Current Task / Quest" box). It is loaded from the card and
  /// saved straight back so editing anything else about an older character
  /// does not erase the starting quest their chats still import. The create
  /// flows dropped their copies because a NEW card has no task to preserve;
  /// this one is load-bearing.
  String _realismCurrentTask = '';
  bool _realismVerificationEnabled = false;
  int _realismVerificationMaxReprocesses = 1;
  int _realismVerificationStrictness = 3;
  bool _realismNeedsDirectorAuthority = false;
  int _needsSimStrength =
      1; // 1-5 multiplier for needs deltas (injected to model + Director)

  // Per-need baseline values (0-100).
  int _needsBaselineHunger = 80;
  int _needsBaselineBladder = 80;
  int _needsBaselineEnergy = 80;
  int _needsBaselineSocial = 80;
  int _needsBaselineFun = 80;
  int _needsBaselineHygiene = 80;
  int _needsBaselineComfort = 80;

  int _needsDecayHunger = 5;
  int _needsDecayBladder = 5;
  int _needsDecayEnergy = 5;
  int _needsDecaySocial = 5;
  int _needsDecayFun = 5;
  int _needsDecayHygiene = 5;
  int _needsDecayComfort = 5;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.character.name);
    _descriptionController = StyledTextController(
      text: widget.character.description,
      preset: StyledTextPreset.macros,
    );
    _personalityController = StyledTextController(
      text: widget.character.personality,
      preset: StyledTextPreset.macros,
    );
    _scenarioController = StyledTextController(
      text: widget.character.scenario,
      preset: StyledTextPreset.macros,
    );
    _firstMessageController = StyledTextController(
      text: widget.character.firstMessage,
      preset: StyledTextPreset.prose,
    );
    _mesExampleController = StyledTextController(
      text: widget.character.mesExample,
      preset: StyledTextPreset.prose,
    );
    _systemPromptController = StyledTextController(
      text: widget.character.systemPrompt,
      preset: StyledTextPreset.macros,
    );
    _postHistoryController = StyledTextController(
      text: widget.character.postHistoryInstructions,
      preset: StyledTextPreset.macros,
    );

    if (widget.character.lorebook != null) {
      _loreEntries = List.from(widget.character.lorebook!.entries);
    } else {
      widget.character.lorebook = Lorebook(entries: []);
      _loreEntries = widget.character.lorebook!.entries;
    }

    _selectedWorldNames = List.from(widget.character.worldNames);
    // Snapshot for the save-time diff: only worlds ADDED in this edit get
    // pushed onto the character's existing chats.
    _initialWorldNames = List.from(widget.character.worldNames);

    _altGreetingControllers = widget.character.alternateGreetings
        .map(
          (g) => StyledTextController(text: g, preset: StyledTextPreset.prose),
        )
        .toList();
    _altGreetingSeeds = alignGreetingSeeds(
      widget.character.frontPorchExtensions?.greetingSeeds ?? const [],
      _altGreetingControllers.length,
    );

    _tags = List.from(widget.character.tags);
    _ttsVoice = widget.character.ttsVoice ?? '';

    // Seed realism state from existing extensions (or keep defaults)
    final ext = widget.character.frontPorchExtensions;
    if (ext != null) {
      _realismEnabled = ext.realismEnabled;
      _realismTimeOfDay = ext.timeOfDay;
      _realismDayCount = ext.dayCount;
      _realismStoryStartDate = ext.storyStartDate;
      _realismStoryStartTime = ext.storyStartTime;
      _realismShortTermBond = ext.shortTermBond;
      _realismLongTermBond = ext.longTermBond;
      _realismTrustLevel = ext.trustLevel;
      _realismEmotion = ext.characterEmotion;
      _realismEmotionIntensity = ext.emotionIntensity;
      _realismNsfwCooldown = ext.nsfwCooldownEnabled;
      _realismPassageOfTime = ext.passageOfTimeEnabled;
      _realismChaosMode = ext.chaosModeEnabled;
      _realismNeedsSim = ext.needsSimEnabled;
      _realismEnjoysLowHygiene = ext.enjoysLowHygiene;
      _realismCurrentTask = ext.currentTask;
      _realismVerificationEnabled = ext.realismVerificationEnabled;
      _realismVerificationMaxReprocesses =
          ext.realismVerificationMaxReprocesses;
      _realismVerificationStrictness = ext.realismVerificationStrictness;
      _realismNeedsDirectorAuthority = ext.realismNeedsDirectorAuthority;
      _needsSimStrength = ext.needsSimStrength;
      _needsBaselineHunger = ext.needsBaselineHunger;
      _needsBaselineBladder = ext.needsBaselineBladder;
      _needsBaselineEnergy = ext.needsBaselineEnergy;
      _needsBaselineSocial = ext.needsBaselineSocial;
      _needsBaselineFun = ext.needsBaselineFun;
      _needsBaselineHygiene = ext.needsBaselineHygiene;
      _needsBaselineComfort = ext.needsBaselineComfort;

      _needsDecayHunger = ext.needsDecayHunger;
      _needsDecayBladder = ext.needsDecayBladder;
      _needsDecayEnergy = ext.needsDecayEnergy;
      _needsDecaySocial = ext.needsDecaySocial;
      _needsDecayFun = ext.needsDecayFun;
      _needsDecayHygiene = ext.needsDecayHygiene;
      _needsDecayComfort = ext.needsDecayComfort;
    }
    _ambitions = List<String>.from(
      widget.character.frontPorchExtensions?.ambitions ?? const [],
    );
    _planLines = List<String>.from(
      widget.character.frontPorchExtensions?.planLines ?? const [],
    );
    _occupation = widget.character.frontPorchExtensions?.occupation ?? '';
    _occupationBrief =
        widget.character.frontPorchExtensions?.occupationBrief ?? '';
    _hours = widget.character.frontPorchExtensions?.hours ?? '';
    _workDays = widget.character.frontPorchExtensions?.workDays;
    _birthday = widget.character.frontPorchExtensions?.birthday ?? '';
    _likes = List<String>.from(
      widget.character.frontPorchExtensions?.likes ?? const [],
    );
    _dislikes = List<String>.from(
      widget.character.frontPorchExtensions?.dislikes ?? const [],
    );
    _intimateInto = List<String>.from(
      widget.character.frontPorchExtensions?.intimateInto ?? const [],
    );
    _intimateNotInto = List<String>.from(
      widget.character.frontPorchExtensions?.intimateNotInto ?? const [],
    );
    // Through Pockets.fromJson rather than a hand-rolled cast: it is the one
    // reader that already tolerates both entry shapes a card can carry (a bare
    // string, or {name, state}) and applies the same caps the runtime does.
    final startingPockets = Pockets.fromJson(
      widget.character.frontPorchExtensions?.inventory,
    );
    _worn = startingPockets.wornDisplay;
    _carrying = startingPockets.carryingDisplay;

    _tabController = TabController(length: 4, vsync: this);

    // Listen for token count updates
    for (final c in [
      _nameController,
      _descriptionController,
      _personalityController,
      _scenarioController,
      _firstMessageController,
      _mesExampleController,
      _systemPromptController,
      _postHistoryController,
    ]) {
      c.addListener(_updateTokenCount);
    }
    for (final c in _altGreetingControllers) {
      c.addListener(_updateTokenCount);
    }
    _updateTokenCount();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _personalityController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _mesExampleController.dispose();
    _systemPromptController.dispose();
    _postHistoryController.dispose();
    for (final c in _altGreetingControllers) {
      c.dispose();
    }
    _tagController.dispose();
    _tokenNotifier.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  //  TOKEN COUNTER
  // ═══════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════
  //  AVATAR
  // ═══════════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════════
  //  LOREBOOK CRUD
  // ═══════════════════════════════════════════════════════════════

  Future<void> _addLoreEntry() async {
    final result = await showLorebookEntryDialog(context: context);
    if (result != null) {
      setState(() => _loreEntries.add(result));
    }
  }

  void _removeLoreEntry(int index) {
    setState(() {
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
      setState(() => _loreEntries[index] = result);
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
    setState(() {
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
    if (result == null || result.files.single.path == null) return;

    try {
      final content = await File(result.files.single.path!).readAsString();
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

      setState(() {
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

  // ═══════════════════════════════════════════════════════════════
  //  BUILD — MAIN SCAFFOLD
  // ═══════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
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
          // Floating token counter
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

  // ═══════════════════════════════════════════════════════════════
  //  TAB 1: DETAILS
  // ═══════════════════════════════════════════════════════════════
}
