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
import 'package:front_porch_ai/ui/dialogs/import_character_lore_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

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
  List<StyledTextController> _altGreetingControllers = [];
  List<String> _tags = [];
  final _tagController = TextEditingController();

  /// Long-term ambitions (Living Time §6), one per line. Identity — travels
  /// with the card; per-chat progress lives in the Journal.
  final _ambitionsController = TextEditingController();
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

    _altGreetingControllers = widget.character.alternateGreetings
        .map((g) => StyledTextController(text: g, preset: StyledTextPreset.prose))
        .toList();

    _tags = List.from(widget.character.tags);

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
    _ambitionsController.text =
        (widget.character.frontPorchExtensions?.ambitions ?? const [])
            .join('\n');

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
    _ambitionsController.dispose();
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
  //  SAVE
  // ═══════════════════════════════════════════════════════════════

  Future<void> _saveCharacter() async {
    // Update model
    widget.character.name = _nameController.text;
    widget.character.description = _descriptionController.text;
    widget.character.personality = _personalityController.text;
    widget.character.scenario = _scenarioController.text;
    widget.character.firstMessage = _firstMessageController.text;
    widget.character.mesExample = _mesExampleController.text;
    widget.character.systemPrompt = _systemPromptController.text;
    widget.character.postHistoryInstructions = _postHistoryController.text;
    widget.character.alternateGreetings = _altGreetingControllers
        .map((c) => c.text)
        .where((t) => t.isNotEmpty)
        .toList();
    widget.character.tags = List.from(_tags);
    widget.character.worldNames = _selectedWorldNames;

    // Always persist extensions — even when realism is disabled — so that
    // configured-but-disabled values survive the PNG round-trip. Skipped when
    // the Realism section is hidden (group member): the member's existing
    // realism/needs ext is group state and must be preserved untouched.
    if (widget.showRealismTab &&
        (_realismEnabled ||
            _realismSettingsModified ||
            widget.character.frontPorchExtensions != null)) {
      debugPrint(
        '[_saveCharacter] Saving realism: enabled=$_realismEnabled, modified=$_realismSettingsModified',
      );
      // Use copyWith from existing (if any) to preserve non-realism FP state
      // (colors, font, avatarLocked, etc.) that the bare ctor would drop.
      // stableId is carried by copyWith; ensure after (addresses review Issue 1).
      final base =
          widget.character.frontPorchExtensions ?? FrontPorchExtensions();
      widget.character.frontPorchExtensions = base.copyWith(
        realismEnabled: _realismEnabled,
        shortTermBond: _realismShortTermBond,
        longTermBond: _realismLongTermBond,
        trustLevel: _realismTrustLevel,
        dayCount: _realismDayCount,
        timeOfDay: _realismTimeOfDay,
        characterEmotion: _realismEmotion,
        emotionIntensity: _realismEmotionIntensity,
        nsfwCooldownEnabled: _realismNsfwCooldown,
        passageOfTimeEnabled: _realismPassageOfTime,
        chaosModeEnabled: _realismChaosMode,
        needsSimEnabled: _realismNeedsSim,
        enjoysLowHygiene: _realismEnjoysLowHygiene,
        ambitions: [
          for (final line in _ambitionsController.text.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ],
        currentTask: _realismCurrentTask,
        realismVerificationEnabled: _realismVerificationEnabled,
        realismVerificationMaxReprocesses: _realismVerificationMaxReprocesses,
        realismVerificationStrictness: _realismVerificationStrictness,
        realismNeedsDirectorAuthority: _realismNeedsDirectorAuthority,
        needsSimStrength: _needsSimStrength,
        needsBaselineHunger: _needsBaselineHunger,
        needsBaselineBladder: _needsBaselineBladder,
        needsBaselineEnergy: _needsBaselineEnergy,
        needsBaselineSocial: _needsBaselineSocial,
        needsBaselineFun: _needsBaselineFun,
        needsBaselineHygiene: _needsBaselineHygiene,
        needsBaselineComfort: _needsBaselineComfort,
        needsDecayHunger: _needsDecayHunger,
        needsDecayBladder: _needsDecayBladder,
        needsDecayEnergy: _needsDecayEnergy,
        needsDecaySocial: _needsDecaySocial,
        needsDecayFun: _needsDecayFun,
        needsDecayHygiene: _needsDecayHygiene,
        needsDecayComfort: _needsDecayComfort,
      );
      // Direct assignment (not copyWith): its `?? this.x` pattern cannot
      // CLEAR a nullable field, and "clear the fixed start date back to 'the
      // day the chat starts'" is a real edit.
      widget.character.frontPorchExtensions!
        ..storyStartDate = _realismStoryStartDate
        ..storyStartTime = _realismStoryStartTime;
      widget.character.frontPorchExtensions!.ensureStableId();
    }

    // The portrait is no longer changed from this page (managed in the Avatar
    // Gallery) — re-embed the V2 card data into the current imagePath PNG to
    // preserve the edited extensions/fields.
    final storage = Provider.of<StorageService>(context, listen: false);
    String? targetPngPath;
    if (widget.character.imagePath != null &&
        widget.character.imagePath!.isNotEmpty) {
      final img = widget.character.imagePath!;
      targetPngPath = p.isAbsolute(img)
          ? img
          : p.join(storage.charactersDir.path, img);
    }

    if (targetPngPath != null) {
      try {
        debugPrint(
          '[_saveCharacter] About to save PNG with extensions: ${widget.character.frontPorchExtensions != null}',
        );
        await V2CardService().saveCardAsPng(
          widget.character,
          targetPngPath,
          targetPngPath,
        );
        debugPrint(
          '[_saveCharacter] PNG saved successfully for ${widget.character.name} to $targetPngPath',
        );

        // Verify PNG was written by reading it back immediately
        try {
          final reloaded = await V2CardService().readCard(targetPngPath);
          if (reloaded?.frontPorchExtensions != null) {
            debugPrint(
              '[_saveCharacter] ✓ PNG verification successful: extensions found in saved file',
            );
          } else {
            debugPrint(
              '[_saveCharacter] ✗ PNG verification FAILED: no extensions in saved file!',
            );
          }
        } catch (verifyError) {
          debugPrint(
            '[_saveCharacter] PNG verification read failed: $verifyError',
          );
        }
      } catch (e) {
        debugPrint('Failed to embed V2 card data: $e');
      }
    } else {
      debugPrint(
        '[_saveCharacter] WARNING: targetPngPath is null, skipping PNG save!',
      );
    }

    // Update Lorebook
    if (widget.character.lorebook == null) {
      widget.character.lorebook = Lorebook(entries: _loreEntries);
    } else {
      widget.character.lorebook!.entries = _loreEntries;
    }

    try {
      if (widget.onSaveOverride != null) {
        // Delegated persistence (e.g. a group member → its group row, never the
        // library). The field updates + PNG save above already ran on the card.
        await widget.onSaveOverride!(widget.character);
      } else {
        await Provider.of<CharacterRepository>(
          context,
          listen: false,
        ).updateCharacter(
          widget.character,
        );

        // Refresh the "Enjoys low hygiene" flag in any active chat so that
        // toggling it on the character immediately affects existing sessions
        // (without requiring a database change).
        if (mounted) {
          try {
            final chatService = Provider.of<ChatService>(
              context,
              listen: false,
            );
            chatService.refreshEnjoysLowHygieneFromActiveCharacter();
          } catch (_) {
            // ChatService not available in this context — that's fine.
          }
        }
      }

      if (widget.onSaved != null) {
        await widget.onSaved!(widget.character);
      }

      if (mounted) {
        // Continue mode (e.g. the Stoop update flow): return the saved card so
        // the caller can proceed, instead of the standard "updated" toast + pop.
        if (widget.popWithCardOnSave) {
          Navigator.pop(context, widget.character);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.textPrimary(context), size: 18),
                  const SizedBox(width: 8),
                  const Text('Character updated successfully!'),
                ],
              ),
              backgroundColor: AppColors.cardOf(context),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating character: $e'),
            backgroundColor: AppColors.negativeAccentOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
            const Icon(Icons.edit_note, color: AppColors.formMasterAccent, size: 22),
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
              builder: (context, tokens, child) =>
                  _buildTokenBadge(tokens),
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

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Avatar (read-only). Portrait + expression images are managed
              //    in the Avatar Gallery (right-click a character on the home
              //    grid, or the chat sidebar) — no destructive change here.
              //    Display uses coverImageFileFor (★-aware), not raw imagePath.
              Builder(
                builder: (context) {
                  final cover = _avatarFile;
                  return Center(
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: AppColors.cardOf(context),
                        border: Border.all(
                          color: AppColors.borderOf(context).withValues(alpha: 0.45),
                        ),
                        image: cover != null
                            ? DecorationImage(
                                image: FileImage(cover),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: cover == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 56,
                                  color: AppColors.resolve(
                                    context,
                                    Colors.white.withValues(alpha: 0.15),
                                    Colors.black.withValues(alpha: 0.15),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'No avatar',
                                  style: TextStyle(
                                    color: AppColors.textTertiary(context),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // ── Identity Section ──
              _sectionCard(
                icon: Icons.badge_outlined,
                title: 'Identity',
                color: AppColors.formMasterAccent,
                children: [
                  _styledField(controller: _nameController, label: 'Name'),
                  const SizedBox(height: 16),
                  // Tags
                  _fieldLabel('Tags'),
                  const SizedBox(height: 8),
                  if (_tags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _tags
                          .map(
                            (tag) => Chip(
                              label: Text(
                                tag,
                                style: TextStyle(
                                  color: AppColors.textSecondary(context),
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: AppColors.surfaceContainerOf(context),
                              side: BorderSide.none,
                              deleteIcon: Icon(
                                Icons.close,
                                size: 14,
                                color: AppColors.textTertiary(context),
                              ),
                              onDeleted: () =>
                                  setState(() => _tags.remove(tag)),
                              visualDensity: VisualDensity.compact,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  if (_tags.isNotEmpty) const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 14,
                          ),
                          decoration: _inputDecoration('Add a tag...'),
                          onSubmitted: (value) {
                            final trimmed = value.trim().toLowerCase();
                            if (trimmed.isNotEmpty &&
                                !_tags.contains(trimmed)) {
                              setState(() {
                                _tags.add(trimmed);
                                _tagController.clear();
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: AppColors.formMasterAccent,
                        ),
                        tooltip: 'Add tag',
                        onPressed: () {
                          final trimmed = _tagController.text
                              .trim()
                              .toLowerCase();
                          if (trimmed.isNotEmpty && !_tags.contains(trimmed)) {
                            setState(() {
                              _tags.add(trimmed);
                              _tagController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Personality & World ──
              _sectionCard(
                icon: Icons.psychology_outlined,
                title: 'Personality & World',
                color: AppColors.porchHoneyOf(context),
                children: [
                  _styledField(
                    controller: _descriptionController,
                    label: 'Description',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Physical appearance, backstory, key traits...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _personalityController,
                    label: 'Personality',
                    maxLines: 3,
                    expandable: true,
                    hint: 'How they act, speak, think...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _scenarioController,
                    label: 'Scenario',
                    maxLines: 3,
                    expandable: true,
                    hint: 'The setting, situation, or context...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Advanced Prompts ──
              _sectionCard(
                icon: Icons.settings_suggest_outlined,
                title: 'Advanced Prompts',
                color: AppColors.textTertiary(context),
                collapsed: true,
                children: [
                  _styledField(
                    controller: _systemPromptController,
                    label: 'System Prompt',
                    maxLines: 4,
                    expandable: true,
                    hint: 'Custom system prompt for this character...',
                  ),
                  const SizedBox(height: 16),
                  _styledField(
                    controller: _postHistoryController,
                    label: 'Post-History Instructions',
                    maxLines: 3,
                    expandable: true,
                    hint: 'Injected after chat history (jailbreak/reminder)...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Ambitions (Living Time §6) ──
              _styledField(
                controller: _ambitionsController,
                label: 'Long-term Ambitions (one per line)',
                maxLines: 3,
                hint:
                    'e.g. Open my own bakery\nThe character works toward '
                    'these across the whole story — progress moves when '
                    'their objectives complete, and lands in the Journal '
                    'and "Our Story" timeline.',
              ),
              const SizedBox(height: 20),

              // ── Realism Engine Summary ── (hidden for group members, whose
              // realism/needs are group state edited in Group Settings)
              if (widget.showRealismTab) _buildRealismSection(),

              const SizedBox(height: 80), // Space for token badge
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 2: DIALOGUE
  // ═══════════════════════════════════════════════════════════════

  Widget _buildDialogueTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── First Message ──
              _sectionCard(
                icon: Icons.chat_bubble_outline,
                title: 'First Message',
                color: AppColors.formMasterAccent,
                children: [
                  _styledField(
                    controller: _firstMessageController,
                    label: 'Opening Message',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        'The character\'s opening line when a conversation starts...',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Alternate Greetings ──
              _sectionCard(
                icon: Icons.swap_horiz,
                title: 'Alternate Greetings',
                color: AppColors.porchHoneyOf(context),
                trailing: TextButton.icon(
                  onPressed: () {
                    setState(() {
                      final c = StyledTextController(preset: StyledTextPreset.prose);
                      c.addListener(_updateTokenCount);
                      _altGreetingControllers.add(c);
                    });
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.formMasterAccent,
                  ),
                ),
                children: [
                  if (_altGreetingControllers.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No alternate greetings yet',
                          style: TextStyle(
                            color: AppColors.resolve(context, Colors.white.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.25)),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    ..._altGreetingControllers.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final ctrl = entry.value;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: idx < _altGreetingControllers.length - 1
                              ? 12
                              : 0,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _styledField(
                                controller: ctrl,
                                label: 'Greeting ${idx + 2}',
                                maxLines: 4,
                                expandable: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 26),
                              child: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _altGreetingControllers[idx].dispose();
                                    _altGreetingControllers.removeAt(idx);
                                  });
                                },
                                icon: Icon(
                                  Icons.remove_circle_outline,
                                  color: AppColors.negativeAccentOf(context),
                                  size: 20,
                                ),
                                tooltip: 'Remove greeting',
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 20),

              // ── Example Dialogue ──
              _sectionCard(
                icon: Icons.format_quote_outlined,
                title: 'Example Dialogue',
                color: AppColors.porchTerracottaOf(context),
                children: [
                  _styledField(
                    controller: _mesExampleController,
                    label: 'Example Conversations',
                    maxLines: 6,
                    expandable: true,
                    hint:
                        '<START>\n{{user}}: Hello!\n{{char}}: *smiles warmly*',
                  ),
                ],
              ),

              const SizedBox(height: 80), // Space for token badge
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 3: LOREBOOK
  // ═══════════════════════════════════════════════════════════════

  Widget _buildLorebookTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lorebook',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'World lore entries inject context when keywords are detected.',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _importLorebookJson,
                    icon: const Icon(Icons.cloud_upload, size: 18),
                    label: const Text('Import file'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      foregroundColor: AppColors.textPrimary(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _importLoreFromCharacter,
                    icon: const Icon(Icons.person_search, size: 18),
                    label: const Text('From character'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.surfaceContainerOf(context),
                      foregroundColor: AppColors.textPrimary(context),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _addLoreEntry,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add Entry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.formMasterAccent,
                      foregroundColor: AppColors.onChaosAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (_loreEntries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(40),
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.45)),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.menu_book_outlined,
                          size: 48,
                          color: AppColors.resolve(context, Colors.white.withValues(alpha: 0.12), Colors.black.withValues(alpha: 0.12)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No lorebook entries yet',
                          style: TextStyle(color: AppColors.textTertiary(context), fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Add entries to inject context-aware world lore.',
                          style: TextStyle(color: AppColors.textTertiary(context), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._loreEntries.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final lore = entry.value;
                  return _buildLoreCard(idx, lore);
                }),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoreCard(int index, LorebookEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          width: 1.5,
          color: entry.constant
              ? AppColors.porchAmberOf(context).withValues(alpha: 0.3)
              : entry.enabled
              ? AppColors.formMasterAccent.withValues(alpha: 0.15)
              : AppColors.borderOf(context).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book,
                size: 14,
                color: entry.constant
                    ? AppColors.porchAmberOf(context)
                    : entry.enabled
                    ? AppColors.formMasterAccent
                    : AppColors.textTertiary(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.displayName,
                  style: TextStyle(
                    color: entry.enabled
                        ? AppColors.textPrimary(context)
                        : AppColors.textTertiary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.porchAmberOf(context).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Always Active',
                    style: TextStyle(
                      color: AppColors.porchAmberOf(context),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (!entry.constant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Depth ${entry.stickyDepth}',
                    style: const TextStyle(
                      color: AppColors.formMasterAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              Tooltip(
                message: entry.enabled
                    ? 'Disable — entry won\'t be matched'
                    : 'Enable — entry will match on its keys',
                child: Switch(
                  value: entry.enabled,
                  onChanged: (val) {
                    setState(() {
                      entry.enabled = val;
                    });
                  },
                  activeTrackColor: AppColors.formMasterAccent.withValues(alpha: 0.5),
                  activeThumbColor: AppColors.formMasterAccent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              IconButton(
                onPressed: () => _editLoreEntry(index),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.textTertiary(context),
                ),
                tooltip: 'Edit entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
              IconButton(
                onPressed: () => _removeLoreEntry(index),
                icon: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: AppColors.negativeAccentOf(context),
                ),
                tooltip: 'Delete entry',
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
              ),
            ],
          ),
          if (entry.key.isNotEmpty && !entry.constant) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              children: entry.keys
                  .map(
                    (k) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.resolve(context, Colors.white.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.05)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        k.trim(),
                        style: TextStyle(
                          color: AppColors.textSecondary(context),
                          fontSize: 10,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  TAB 4: WORLDS
  // ═══════════════════════════════════════════════════════════════

  Widget _buildWorldsTab() {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Linked Places',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Attach places (Worlds) so their lore and climate apply in this character\'s chats. '
                    'To copy another character\'s lore into this card, use Lorebook → From character.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary(context)),
                  ),
                  const SizedBox(height: 20),

                  if (repo.placeWorlds.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: AppColors.cardOf(context),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.45)),
                      ),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.public,
                              size: 48,
                              color: AppColors.resolve(context, Colors.white.withValues(alpha: 0.12), Colors.black.withValues(alpha: 0.12)),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No places found',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Create places in the Worlds section.',
                              style: TextStyle(
                                color: AppColors.textTertiary(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...repo.placeWorlds.map((world) {
                      final isLinked = _selectedWorldNames.contains(world.id) ||
                          _selectedWorldNames.contains(world.name);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.cardOf(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isLinked
                                ? AppColors.formMasterAccent.withValues(alpha: 0.4)
                                : AppColors.borderOf(context).withValues(alpha: 0.45),
                          ),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isLinked
                                  ? AppColors.formMasterAccent.withValues(alpha: 0.2)
                                  : AppColors.resolve(context, Colors.white.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.public,
                              size: 20,
                              color: isLinked
                                  ? AppColors.formMasterAccent
                                  : AppColors.textTertiary(context),
                            ),
                          ),
                          title: Text(
                            world.name,
                            style: TextStyle(
                              color: isLinked ? AppColors.textPrimary(context) : AppColors.textSecondary(context),
                              fontWeight: isLinked
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          subtitle: Text(
                            world.description.isNotEmpty
                                ? world.description
                                : '${world.lorebook.entries.length} entries',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 12,
                            ),
                          ),
                          trailing: Switch(
                            value: isLinked,
                            onChanged: (val) {
                              setState(() {
                                if (val) {
                                  _selectedWorldNames.remove(world.name);
                                  if (!_selectedWorldNames.contains(world.id)) {
                                    _selectedWorldNames.add(world.id);
                                  }
                                } else {
                                  _selectedWorldNames.remove(world.id);
                                  _selectedWorldNames.remove(world.name);
                                }
                              });
                            },
                            activeTrackColor: AppColors.formMasterAccent.withValues(
                              alpha: 0.5,
                            ),
                            activeThumbColor: AppColors.formMasterAccent,
                          ),
                        ),
                      );
                    }),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  REALISM ENGINE SUMMARY (read-only)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildRealismSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Playful disclaimer note
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.formMasterAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.formMasterAccent.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('😉', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These settings only affect new conversations with this character — '
                  'your existing chats won\'t be changed. No cheating with the relationship values!',
                  style: TextStyle(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.8),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Full editable Realism Engine form
        RealismFormSection(
          enabled: _realismEnabled,
          onEnabledChanged: (v) => setState(() {
            _realismEnabled = v;
            _realismSettingsModified = true;
          }),
          timeOfDay: _realismTimeOfDay,
          onTimeOfDayChanged: (v) => setState(() {
            _realismTimeOfDay = v;
            _realismSettingsModified = true;
          }),
          dayCount: _realismDayCount,
          onDayCountChanged: (v) => setState(() {
            _realismDayCount = v;
            _realismSettingsModified = true;
          }),
          storyStartDate: _realismStoryStartDate,
          onStoryStartDateChanged: (v) => setState(() {
            _realismStoryStartDate = v;
            _realismSettingsModified = true;
          }),
          storyStartTime: _realismStoryStartTime,
          onStoryStartTimeChanged: (v) => setState(() {
            _realismStoryStartTime = v;
            _realismSettingsModified = true;
          }),
          shortTermBond: _realismShortTermBond,
          onShortTermBondChanged: (v) => setState(() {
            _realismShortTermBond = v;
            _realismSettingsModified = true;
          }),
          longTermBond: _realismLongTermBond,
          onLongTermBondChanged: (v) => setState(() {
            _realismLongTermBond = v;
            _realismSettingsModified = true;
          }),
          trustLevel: _realismTrustLevel,
          onTrustLevelChanged: (v) => setState(() {
            _realismTrustLevel = v;
            _realismSettingsModified = true;
          }),
          emotion: _realismEmotion,
          onEmotionChanged: (v) => setState(() {
            _realismEmotion = v;
            _realismSettingsModified = true;
          }),
          emotionIntensity: _realismEmotionIntensity,
          onEmotionIntensityChanged: (v) => setState(() {
            _realismEmotionIntensity = v;
            _realismSettingsModified = true;
          }),
          nsfwCooldownEnabled: _realismNsfwCooldown,
          onNsfwCooldownChanged: (v) => setState(() {
            _realismNsfwCooldown = v;
            _realismSettingsModified = true;
          }),
          chaosModeEnabled: _realismChaosMode,
          onChaosModeChanged: (v) => setState(() {
            _realismChaosMode = v;
            _realismSettingsModified = true;
          }),
          currentTask: _realismCurrentTask,
          onCurrentTaskChanged: (v) => setState(() {
            _realismCurrentTask = v;
            _realismSettingsModified = true;
          }),
          realismVerificationEnabled: _realismVerificationEnabled,
          onRealismVerificationChanged: (v) => setState(() {
            _realismVerificationEnabled = v;
            _realismSettingsModified = true;
          }),
          realismVerificationMaxReprocesses: _realismVerificationMaxReprocesses,
          onRealismVerificationMaxReprocessesChanged: (v) => setState(() {
            _realismVerificationMaxReprocesses = v;
            _realismSettingsModified = true;
          }),
          realismVerificationStrictness: _realismVerificationStrictness,
          onRealismVerificationStrictnessChanged: (v) => setState(() {
            _realismVerificationStrictness = v;
            _realismSettingsModified = true;
          }),
          needsFormSection: NeedsFormSection(
            enabled: _realismNeedsSim,
            onEnabledChanged: (v) => setState(() {
              _realismNeedsSim = v;
              _realismSettingsModified = true;
            }),
            enjoysLowHygiene: _realismEnjoysLowHygiene,
            onEnjoysLowHygieneChanged: (v) => setState(() {
              _realismEnjoysLowHygiene = v;
              _realismSettingsModified = true;
            }),
            needsSimStrength: _needsSimStrength,
            onNeedsSimStrengthChanged: (v) => setState(() {
              _needsSimStrength = v;
              _realismSettingsModified = true;
            }),
            baselineHunger: _needsBaselineHunger,
            onBaselineHungerChanged: (v) => setState(() {
              _needsBaselineHunger = v;
              _realismSettingsModified = true;
            }),
            baselineBladder: _needsBaselineBladder,
            onBaselineBladderChanged: (v) => setState(() {
              _needsBaselineBladder = v;
              _realismSettingsModified = true;
            }),
            baselineEnergy: _needsBaselineEnergy,
            onBaselineEnergyChanged: (v) => setState(() {
              _needsBaselineEnergy = v;
              _realismSettingsModified = true;
            }),
            baselineSocial: _needsBaselineSocial,
            onBaselineSocialChanged: (v) => setState(() {
              _needsBaselineSocial = v;
              _realismSettingsModified = true;
            }),
            baselineFun: _needsBaselineFun,
            onBaselineFunChanged: (v) => setState(() {
              _needsBaselineFun = v;
              _realismSettingsModified = true;
            }),
            baselineHygiene: _needsBaselineHygiene,
            onBaselineHygieneChanged: (v) => setState(() {
              _needsBaselineHygiene = v;
              _realismSettingsModified = true;
            }),
            baselineComfort: _needsBaselineComfort,
            onBaselineComfortChanged: (v) => setState(() {
              _needsBaselineComfort = v;
              _realismSettingsModified = true;
            }),
            decayHunger: _needsDecayHunger,
            onDecayHungerChanged: (v) => setState(() {
              _needsDecayHunger = v;
              _realismSettingsModified = true;
            }),
            decayBladder: _needsDecayBladder,
            onDecayBladderChanged: (v) => setState(() {
              _needsDecayBladder = v;
              _realismSettingsModified = true;
            }),
            decayEnergy: _needsDecayEnergy,
            onDecayEnergyChanged: (v) => setState(() {
              _needsDecayEnergy = v;
              _realismSettingsModified = true;
            }),
            decaySocial: _needsDecaySocial,
            onDecaySocialChanged: (v) => setState(() {
              _needsDecaySocial = v;
              _realismSettingsModified = true;
            }),
            decayFun: _needsDecayFun,
            onDecayFunChanged: (v) => setState(() {
              _needsDecayFun = v;
              _realismSettingsModified = true;
            }),
            decayHygiene: _needsDecayHygiene,
            onDecayHygieneChanged: (v) => setState(() {
              _needsDecayHygiene = v;
              _realismSettingsModified = true;
            }),
            decayComfort: _needsDecayComfort,
            onDecayComfortChanged: (v) => setState(() {
              _needsDecayComfort = v;
              _realismSettingsModified = true;
            }),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  SHARED WIDGETS
  // ═══════════════════════════════════════════════════════════════

  /// Glassmorphic section card with icon header.
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
    Widget? trailing,
    bool collapsed = false,
  }) {
    final header = Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (trailing != null) ...[const Spacer(), trailing],
      ],
    );

    if (collapsed) {
      // Material, not a decorated Container: ExpansionTile's header is a
      // ListTile, which paints its background and ink splash onto the nearest
      // Material ancestor — a coloured DecoratedBox in between swallows the
      // ripple. Flutter 3.44 asserts on this ("ListTile background color or
      // ink splashes may be invisible"). Same colour, radius and border; the
      // header ripple now actually renders.
      return Material(
        color: AppColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: AppColors.borderOf(context).withValues(alpha: 0.45),
          ),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: AppColors.iconSecondary(context),
            collapsedIconColor: AppColors.iconSecondary(context),
            children: children,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [header, const SizedBox(height: 16), ...children],
      ),
    );
  }

  /// Styled text field matching the manual creator design.
  Widget _styledField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    bool expandable = false,
    bool enabled = true,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _fieldLabel(label),
            if (expandable) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => showExpandedEditorDialog(
                  context: context,
                  title: label,
                  controller: controller,
                  hintText: 'Enter $label...',
                ),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Tooltip(
                    message: 'Open fullscreen editor',
                    child: Icon(
                      Icons.open_in_full,
                      size: 14,
                      color: AppColors.resolve(context, Colors.white.withValues(alpha: 0.25), Colors.black.withValues(alpha: 0.25)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        AppTextField(
          controller: controller,
          maxLines: maxLines,
          enabled: enabled,
          style: TextStyle(
            color: enabled ? AppColors.textPrimary(context) : AppColors.textTertiary(context),
            fontSize: 14,
          ),
          decoration: _inputDecoration(hint ?? 'Enter $label...'),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textTertiary(context), fontSize: 13),
      filled: true,
      fillColor: AppColors.backgroundOf(context),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.45)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _borderFocus),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.resolve(context, Colors.white.withValues(alpha: 0.04), Colors.black.withValues(alpha: 0.04))),
      ),
      contentPadding: const EdgeInsets.all(14),
    );
  }
}
