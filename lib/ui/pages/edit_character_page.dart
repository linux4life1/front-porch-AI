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
part 'edit_character_page.tab_dialogue.dart';
part 'edit_character_page.tabs_lore.dart';
part 'edit_character_page.host.dart';

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

  @override
  Widget build(BuildContext context) => _buildHost(context);
}
