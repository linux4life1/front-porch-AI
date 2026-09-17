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
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/lorebook_entry_dialog.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/group_alternate_greetings_editor.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';
import 'package:front_porch_ai/ui/widgets/story_begins_row.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/widgets/relationship_scale.dart'
    show relationshipTierName, relationshipScaleColor;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'package:front_porch_ai/database/database.dart' as db;

part 'create_group_chat_page.member_realism_card.dart';
part 'create_group_chat_page.steps_cast.dart';
part 'create_group_chat_page.steps_dynamics.dart';
part 'create_group_chat_page.steps_lore.dart';
part 'create_group_chat_page.steps_opening.dart';
part 'create_group_chat_page.steps_realism.dart';
part 'create_group_chat_page.steps_review.dart';

/// First-class, menu-driven Group Chat Creator (pure create flow).
///
/// Launched from the sidebar "Create Group" button.
/// Uses the exact same linear step wizard UI (top-bar dots, _currentStep,
/// AnimatedSwitcher, _buildNavButtons) as create_character_page.dart.
/// Edit flows now use the dedicated tabbed EditGroupPage (matching EditCharacterPage style).
class CreateGroupChatPage extends StatefulWidget {
  const CreateGroupChatPage({super.key});

  @override
  State<CreateGroupChatPage> createState() => _CreateGroupChatPageState();
}

class _CreateGroupChatPageState extends State<CreateGroupChatPage> {
  /// Re-exposes the protected [setState] for the `part of` extensions
  /// (`create_group_chat_page.*.dart`) — the wizard step builders can't call
  /// a State's protected members directly. Same bridge as settings_page.dart
  /// and chat_page.dart.
  void rebuildState(VoidCallback fn) => setState(fn);

  int _currentStep = 0;
  // 0 = Members
  // 1 = Identity
  // 2 = Opening
  // 3 = Prompts
  // 4 = Lore
  // 5 = Realism
  // 6 = Group Dynamics (only for groups of 4 or fewer)
  // 7 = Review

  // ── Core State ─────────────────────────────────────────────────────
  final List<CharacterCard> _members = [];
  // (reserved for future multi-select voice bulk actions)

  // Identity
  final _nameController = TextEditingController();

  // Behavior
  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorMode = false;

  // Opening
  final _scenarioController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  final _firstMessageController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  List<String> _altGreetings = [];
  List<GreetingRealismSeed?> _altGreetingSeeds = [];
  bool _isGeneratingScenario = false;
  bool _isGeneratingFirst = false;

  // Prompts
  final _groupSystemController = StyledTextController(
    preset: StyledTextPreset.prose,
  );
  final Map<String, TextEditingController> _characterSystemPrompts =
      {}; // charId -> prompt

  // Voices (charId -> voiceId or '')
  final Map<String, String> _characterVoices = {};

  // Lore & Worlds
  final List<LorebookEntry> _groupLoreEntries = [];
  final List<String> _worldIds = [];
  bool _inheritCharacterLorebooks = false;
  // (reserved for future entry dialog state if we go non-modal)

  // Realism / Chaos / Needs (group level + per-member seeds)
  bool _realismEnabled =
      true; // Master group toggle — this is the only realism on/off control
  final Map<String, Map<String, dynamic>> _memberRealismSeeds = {};
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;
  bool _needsSimEnabled = true;

  // Per-member needs baselines (0-100) — mirrors _memberRealismSeeds keys.
  final Map<String, Map<String, int>> _memberNeedsBaselines = {};

  // Global time/day for the whole group (not per-character — prevents footgun)
  String _globalTimeOfDay = 'morning';
  int _globalDayCount = 1;
  // Story Calendar authoring (story-calendar.md §3a): null start date =
  // "the day the chat starts"; null time = period default.
  String? _globalStoryStartDate;
  String? _globalStoryStartTime;

  // Token-ish estimate (lightweight)
  int _contentTokenEstimate = 0;

  @override
  void initState() {
    super.initState();

    _nameController.addListener(_updateEstimates);
    _scenarioController.addListener(_updateEstimates);
    _firstMessageController.addListener(_updateEstimates);
    _groupSystemController.addListener(_updateEstimates);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _groupSystemController.dispose();
    // Dispose per-character controllers
    for (final ctrl in _characterSystemPrompts.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _updateEstimates() {
    int total = 0;
    total += (_nameController.text.length / 4).ceil();
    total += (_scenarioController.text.length / 4).ceil();
    total += (_firstMessageController.text.length / 4).ceil();
    total += (_groupSystemController.text.length / 4).ceil();
    for (final ctrl in _characterSystemPrompts.values) {
      total += (ctrl.text.length / 4).ceil();
    }
    for (final e in _groupLoreEntries) {
      total += ((e.name.length + e.key.length + e.content.length) / 4).ceil();
    }
    if (mounted && total != _contentTokenEstimate) {
      setState(() => _contentTokenEstimate = total);
    }
  }

  List<CharacterCard> get _availableCharacters {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final all = repo.characters;
    final memberIds = _members.map(_stableId).toSet();
    return all.where((c) => !memberIds.contains(_stableId(c))).toList();
  }

  /// Delegates to the canonical stable group ID.
  /// See [StableGroupId.stableGroupId] in lib/utils/character_id.dart
  String _stableId(CharacterCard c) => c.stableGroupId;

  // ── SECTION NAV ────────────────────────────────────────────────────

  bool get _canLeaveMembersStep => _members.length >= 2;

  int? _getEffectiveNextStep(int current) {
    int next = current + 1;

    // Skip Group Dynamics (now step 5) if group is too large
    if (next == 5 && _members.length > 4) {
      next = 6; // jump to Opening
    }

    if (next > 7) return null; // beyond Review
    return next;
  }

  void _goToPreviousStep(int current) {
    int prev = current - 1;

    // If we are coming back from Review and skipped Dynamics, go to Realism instead
    if (current == 7 && _members.length > 4) {
      prev = 4; // Realism
    }

    if (prev < 0) prev = 0;
    setState(() => _currentStep = prev);
  }

  // ── MEMBER MANAGEMENT (heart of the experience) ────────────────────

  void _addMember(CharacterCard card) {
    final id = _stableId(card);
    if (_members.any((m) => _stableId(m) == id)) return;
    setState(() {
      _members.add(card);
      // Seed a reasonable neutral realism entry if none exists
      if (!_memberRealismSeeds.containsKey(id)) {
        _memberRealismSeeds[id] = _defaultRealismSeedFor(card);
      }
      if (!_memberNeedsBaselines.containsKey(id)) {
        final s = _memberRealismSeeds[id]!;
        _memberNeedsBaselines[id] = {
          'hunger': s['needsBaselineHunger'] as int? ?? 80,
          'bladder': s['needsBaselineBladder'] as int? ?? 80,
          'energy': s['needsBaselineEnergy'] as int? ?? 80,
          'social': s['needsBaselineSocial'] as int? ?? 80,
          'fun': s['needsBaselineFun'] as int? ?? 80,
          'hygiene': s['needsBaselineHygiene'] as int? ?? 80,
          'comfort': s['needsBaselineComfort'] as int? ?? 80,
          'decayHunger': s['needsDecayHunger'] as int? ?? 5,
          'decayBladder': s['needsDecayBladder'] as int? ?? 5,
          'decayEnergy': s['needsDecayEnergy'] as int? ?? 5,
          'decaySocial': s['needsDecaySocial'] as int? ?? 5,
          'decayFun': s['needsDecayFun'] as int? ?? 5,
          'decayHygiene': s['needsDecayHygiene'] as int? ?? 5,
          'decayComfort': s['needsDecayComfort'] as int? ?? 5,
        };
      }

      // Initialize empty relationships map for small groups
      if (_members.length <= 4) {
        final seed = _memberRealismSeeds[id]!;
        seed['relationships'] ??= <String, int>{};
      }

      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _members.map((c) => c.name).join(' & ');
      }
      _updateEstimates();
    });
  }

  void _removeMember(String id) {
    setState(() {
      _members.removeWhere((c) => _stableId(c) == id);
      _characterVoices.remove(id);
      _characterSystemPrompts.remove(id);
      _memberRealismSeeds.remove(id);

      // Clean up any references to this member from other characters' relationship maps
      for (final seed in _memberRealismSeeds.values) {
        final rels = seed['relationships'];
        if (rels is Map) {
          rels.remove(id);
        }
      }

      if (_members.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = _members.map((c) => c.name).join(' & ');
      }
    });
  }

  // onReorderItem (unlike the retired onReorder) delivers newIndex already
  // adjusted for the removal at oldIndex — no manual decrement.
  void _reorderMembers(int oldIndex, int newIndex) {
    setState(() {
      final moved = _members.removeAt(oldIndex);
      _members.insert(newIndex, moved);
    });
  }

  void _setVoice(String charId, String? voiceId) {
    setState(() {
      _characterVoices[charId] = voiceId ?? '';
    });
  }

  // Shared default seed (create + edit parity) lives in group_realism_blobs.dart
  // as defaultGroupMemberRealismSeed(); the card arg is ignored (the seed is a
  // neutral constant) but kept so existing call sites read naturally.
  Map<String, dynamic> _defaultRealismSeedFor(CharacterCard c) =>
      defaultGroupMemberRealismSeed();

  void _seedRealismFromCard(String charId) {
    final card = _members.firstWhere(
      (c) => _stableId(c) == charId,
      orElse: () => _members.first,
    );
    setState(() {
      _memberRealismSeeds[charId] = _defaultRealismSeedFor(card);
    });
  }

  void _bulkSeedRealism(String mode) {
    setState(() {
      for (final c in _members) {
        final id = _stableId(c);
        if (mode == 'neutral') {
          _memberRealismSeeds[id] = _defaultRealismSeedFor(c);
        } else if (mode == 'highBond') {
          final s = _defaultRealismSeedFor(c);
          s['affection'] = 75;
          s['trust'] = 70;
          s['emotion'] = 'affection';
          s['emotionIntensity'] = 'moderate';
          _memberRealismSeeds[id] = s;
        }
      }
    });
  }

  // ── AI GENERATION (adapted + improved from old dialog) ─────────────

  Future<void> _generateScenario({String dynamicsContext = ''}) async {
    final llm = Provider.of<LLMProvider>(context, listen: false);
    final service = llm.activeService;
    if (!service.isReady) {
      _showSnack(
        'LLM backend is not ready. Start KoboldCPP or configure your API first.',
      );
      return;
    }
    setState(() => _isGeneratingScenario = true);

    final briefs = _members
        .map((c) {
          final trait = c.personality.isNotEmpty
              ? c.personality.split('.').first
              : c.name;
          return '${c.name} ($trait)';
        })
        .join(', ');

    final dynamicsCtx = dynamicsContext.isNotEmpty
        ? '\n\nHidden inter-character dynamics to reflect in the setting and atmosphere:\n$dynamicsContext\n\nIncorporate the emotional undercurrents between the characters into the description of the location and situation (without stating them directly).'
        : '';

    final prompt =
        '[Output ONLY the scenario text. No planning, reasoning, or explanation. '
        'Do NOT use <think> tags.]\n\n'
        'Write a brief scenario (1-2 sentences max) for a group roleplay with: $briefs.$dynamicsCtx\n'
        'The scenario should describe WHERE the characters are and WHAT is happening.\n'
        'Use {{user}} to refer to the player when appropriate. Keep it concise.\n\n'
        'SCENARIO: ';

    try {
      final buf = StringBuffer();
      final params = GenerationParams(
        prompt: prompt,
        maxLength: 420,
        temperature: 0.88,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        mandatoryReasoningHeadroom: true,
        stopSequences: ['\n\n', 'END', '---', '<think>'],
      );
      await for (final tok in service.generateStream(params)) {
        buf.write(tok);
      }
      var result = _cleanThinkAndMarkers(
        buf.toString(),
        prefixMarkers: ['SCENARIO:'],
      );
      if (result.isNotEmpty) {
        _scenarioController.text = result;
      }
    } catch (e) {
      _showSnack('Scenario generation failed: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingScenario = false);
    }
  }

  Future<void> _generateFirstMessage({String dynamicsContext = ''}) async {
    final llm = Provider.of<LLMProvider>(context, listen: false);
    final service = llm.activeService;
    if (!service.isReady) {
      _showSnack(
        'LLM backend is not ready. Start KoboldCPP or configure your API first.',
      );
      return;
    }
    setState(() => _isGeneratingFirst = true);

    final descriptions = _members
        .map((c) {
          final persona = c.personality.isNotEmpty
              ? c.personality
              : c.description;
          final scen = c.scenario.isNotEmpty ? ' Scenario: ${c.scenario}' : '';
          return '- ${c.name}: $persona$scen';
        })
        .join('\n');

    final scenarioCtx = _scenarioController.text.trim().isNotEmpty
        ? '\nThe group scenario is: ${_scenarioController.text.trim()}'
        : '';

    final dynamicsCtx = dynamicsContext.isNotEmpty
        ? '\n\n$dynamicsContext\n\nIMPORTANT INSTRUCTIONS FOR USING THE DYNAMICS:\n- These are the characters\' private, hidden feelings toward one another (the player does not know these feelings exist).\n- Use them to create natural tension, chemistry, coldness, protectiveness, jealousy, affection, etc. in the opening scene.\n- Show the dynamics through subtext, body language, tone of voice, who stands near whom, micro-expressions, and how characters speak to (or about) each other.\n- Never have a character explicitly state their numerical score or tier. Reveal it organically through behavior and dialogue.\n- Strong negative scores should create visible friction or wariness. Strong positive scores should create warmth, protectiveness, or instinctive closeness.'
        : '';

    final isDirector = _directorMode;
    final prompt = isDirector
        ? '[INSTRUCTIONS: Output ONLY the creative scene text. '
              'Do NOT plan, reason, analyze, or explain. Do NOT use <think> tags. Start writing IMMEDIATELY.]\n\n'
              'Write a vivid, immersive opening scene (3-5 paragraphs) for a DIRECTOR MODE group roleplay featuring:\n$descriptions$scenarioCtx$dynamicsCtx\n\n'
              'CRITICAL: There is NO user/player present. Characters interact ONLY with each other.\n'
              'Each character MUST have at least 2 lines of dialogue.\n'
              'Characters address and react to EACH OTHER.\n'
              'Use *asterisks* for actions.\n'
              'When done, write "END SCENE" on its own line.\n\n'
              'BEGIN SCENE:\n'
        : '[INSTRUCTIONS: Output ONLY the creative scene text. '
              'Do NOT plan, reason, analyze, or explain. Do NOT use <think> tags. Start writing IMMEDIATELY.]\n\n'
              'Write a vivid, immersive opening message (2-4 paragraphs) for a group roleplay featuring:\n$descriptions$scenarioCtx$dynamicsCtx\n\n'
              'The player ({{user}}) is present. Include natural dialogue from the characters and actions in *asterisks*.\n'
              'Keep it engaging and true to the characters.\n\n'
              'OPENING:\n';

    try {
      final buf = StringBuffer();
      final params = GenerationParams(
        prompt: prompt,
        maxLength: isDirector ? 1800 : 1200,
        temperature: 0.86,
        reasoningEnabled: false,
        reasoningMaxTokens: 0,
        mandatoryReasoningHeadroom: true,
        stopSequences: isDirector
            ? ['END SCENE', '---', '[END]', '<think>']
            : ['\n\n\n', '---', '<think>'],
      );
      await for (final tok in service.generateStream(params)) {
        buf.write(tok);
      }
      var result = _cleanThinkAndMarkers(
        buf.toString(),
        prefixMarkers: ['BEGIN SCENE:', 'OPENING:'],
      );
      if (isDirector) {
        result = result
            .split('\n')
            .where((line) {
              final t = line.trimLeft();
              return !t.startsWith('The user wants') &&
                  !t.startsWith('I need to') &&
                  !t.startsWith('I will') &&
                  !RegExp(
                    r'^\d+\.\s+(Write|Use|Set|Make|Do|Keep|NOT|Create|End)',
                  ).hasMatch(t);
            })
            .join('\n')
            .trim();
      }
      if (result.isNotEmpty) {
        _firstMessageController.text = result;
      }
    } catch (e) {
      _showSnack('First message generation failed: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingFirst = false);
    }
  }

  String _cleanThinkAndMarkers(
    String raw, {
    List<String> prefixMarkers = const [],
  }) {
    var s = raw
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
        .replaceAll('"', '')
        .trim();
    for (final m in prefixMarkers) {
      s = s.replaceAll(RegExp('^$m\\s*', caseSensitive: false), '');
    }
    return s.trim();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── LOREBOOK HELPERS ───────────────────────────────────────────────

  Future<void> _showLoreEntryEditor({
    LorebookEntry? existing,
    int? index,
  }) async {
    final result = await showLorebookEntryDialog(
      context: context,
      existing: existing,
      showEnabled: true,
    );
    if (result != null) {
      setState(() {
        if (index != null && index >= 0 && index < _groupLoreEntries.length) {
          _groupLoreEntries[index] = result;
        } else {
          _groupLoreEntries.add(result);
        }
        _updateEstimates();
      });
    }
  }

  void _deleteLoreEntry(int index) {
    setState(() => _groupLoreEntries.removeAt(index));
  }

  /// Builds a rich, explanatory summary of the current hidden inter-character
  /// relationships (from the Group Dynamics step) to feed into AI generation.
  /// Includes guidance on the -300 to +300 scale so the model actually understands
  /// how to use the data when writing the opening scene.
  String _buildDynamicsContextForGeneration() {
    if (_members.length > 4) return '';

    final buffer = StringBuffer();
    buffer.writeln(
      'Hidden inter-character dynamics (these are private feelings the characters have toward each other — the player does not know about them):',
    );
    buffer.writeln(
      'Scale explanation: Values range from -300 (extreme hatred/resentment) to +300 (deep soul-level bond).',
    );
    buffer.writeln(
      'Rough tiers: 80+ = Soulbound / extremely devoted, 50+ = Deep Bond, 20+ = Close, 5+ = Friendly, -4 to +4 = Neutral, -5 to -19 = Uneasy, -20 to -49 = Distant, -50 to -79 = Hostile, -80 and below = Nemesis / intense personal animosity.',
    );
    buffer.writeln('');

    for (final source in _members) {
      final sourceId = _stableId(source);
      final seed = _memberRealismSeeds[sourceId];
      final rels = (seed?['relationships'] as Map?)?.cast<String, int>() ?? {};
      if (rels.isEmpty) continue;

      for (final entry in rels.entries) {
        final target = _members.firstWhere(
          (m) => _stableId(m) == entry.key,
          orElse: () => source,
        );
        if (target == source) continue;

        final value = entry.value;
        final tier = relationshipTierName(value);
        buffer.writeln(
          '- ${source.name} feels ${tier.toLowerCase()} toward ${target.name} (score: $value on -300 to +300 scale)',
        );
      }
    }

    buffer.writeln('');
    buffer.writeln(
      'When writing the opening scene, reflect these private feelings naturally through body language, tone, subtext, and how the characters interact with each other. Do not state the scores directly.',
    );

    return buffer.toString().trim();
  }

  // ── WORLD HELPERS ──────────────────────────────────────────────────

  void _toggleWorld(String worldId) {
    setState(() {
      if (_worldIds.contains(worldId)) {
        _worldIds.remove(worldId);
      } else {
        _worldIds.add(worldId);
      }
    });
  }

  // ── REALISM HELPERS ────────────────────────────────────────────────

  void _updateMemberRealism(String charId, Map<String, dynamic> values) {
    setState(() {
      _memberRealismSeeds[charId] = {
        ...(_memberRealismSeeds[charId] ??
            _defaultRealismSeedFor(
              _members.firstWhere((c) => _stableId(c) == charId),
            )),
        ...values,
      };
    });
  }

  // ── SAVE (unified create + edit; extended existing method, 0 new private methods) ──

  Future<void> _createGroup({bool enterChat = true}) async {
    if (_members.length < 2) {
      _showSnack('A group needs at least 2 characters.');
      setState(() => _currentStep = 0);
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Please give the group a name.');
      setState(() => _currentStep = 1);
      return;
    }

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    Provider.of<TtsService>(
      context,
      listen: false,
    ); // voices already resolved earlier

    // Per-char system prompts + realism/needs/dynamics seeds must be keyed by the
    // RUNTIME member id (the fresh `mid` generated per member in the insert loop
    // below), NOT the source library card's id. Every runtime read — the realism
    // engine (`_groupRealism[id]`), baseline lookups, and per-member prompt reads
    // — keys off the member's own UUID. So we collect the source-id → mid mapping
    // while inserting members and build both blobs (and the prompt map) from that
    // mapping AFTER the loop. Historically these were keyed by the source id and
    // were therefore never found at runtime (bond/trust/emotion/relationships and
    // per-member prompts silently fell back to defaults). See remapSeedsToMemberIds
    // + test/utils/group_realism_blobs_test.dart for the reachability proof.
    final charPrompts = <String, String>{};
    final memberIdMap = <String, String>{}; // source stableId → member mid

    // Serialize group lorebook
    final lb = Lorebook(entries: List.from(_groupLoreEntries));
    final groupLoreJson = jsonEncode(lb.toJson());

    String baselineJson = '{}';
    String defaultMemberJson = '{}';

    final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';

    // Persist decoupled members to private storage + typed table (extends this existing method;
    // reuses generalized duplicateCharacter for copy+ V2 embed into groups/<id>/avatars/).
    // No new private methods. Library untouched (sole bridge remains explicit "Separate...").
    final storage = Provider.of<StorageService>(context, listen: false);
    final database = Provider.of<db.AppDatabase>(context, listen: false);
    for (final source in _members) {
      final mid = const Uuid().v4();
      final avDir = Directory(
        p.join(storage.groupsDir.path, groupId, 'avatars'),
      );
      await avDir.create(recursive: true);

      await repo.duplicateCharacter(
        source,
        targetDirOverride: avDir.path,
        forcedBasename: mid,
        skipLibraryInsert: true,
      );

      // Per-member authority + verif flags + needs strength (exponent 1-5) must propagate
      // to the GroupMember row's frontPorchExtensions (the source of truth for runtime _groupCharacters cards
      // via toCharacterCard + god impersonation cb reads of .frontPorchExtensions.* ).
      // Seeds already feed full (incl short keys) to defaultMemberRealismState perChar; baseline scalars only.
      // Patch here (not mutate source library card) so group instance gets UI choice; duplicate only for avatar/PNG.
      // Consistent for all flags; other add-member paths use passed card's ext.
      final id = _stableId(source);
      // Record source-id → mid so the realism/baseline blobs (built after this
      // loop) and per-member prompts are keyed by the id the runtime reads.
      memberIdMap[id] = mid;
      final promptCtrl = _characterSystemPrompts[id];
      if (promptCtrl != null && promptCtrl.text.trim().isNotEmpty) {
        charPrompts[mid] = promptCtrl.text.trim();
      }
      final seed = _memberRealismSeeds[id] ?? _defaultRealismSeedFor(source);
      FrontPorchExtensions? memberFp;
      if (source.frontPorchExtensions != null) {
        memberFp = source.frontPorchExtensions!.copyWith(
          enjoysLowHygiene:
              (seed['enjoysLowHygiene'] as bool?) ??
              source.frontPorchExtensions!.enjoysLowHygiene,
          realismVerificationEnabled:
              (seed['verificationEnabled'] as bool?) ??
              source.frontPorchExtensions!.realismVerificationEnabled,
          realismVerificationMaxReprocesses:
              (seed['verificationMaxReprocesses'] as int?) ??
              source.frontPorchExtensions!.realismVerificationMaxReprocesses,
          realismVerificationStrictness:
              (seed['verificationStrictness'] as int?) ??
              source.frontPorchExtensions!.realismVerificationStrictness,
          realismNeedsDirectorAuthority:
              (seed['needsDirectorAuthority'] as bool?) ??
              source.frontPorchExtensions!.realismNeedsDirectorAuthority,
          needsSimStrength:
              (seed['needsSimStrength'] as int?) ??
              source.frontPorchExtensions!.needsSimStrength,
          // Carry the group-creator's per-member needs baselines + decay
          // choices (the seed). Without these two blocks, cards that already
          // ship a FrontPorchExtensions (the common case) silently lost every
          // baseline/decay adjustment made in the creator at save time.
          needsBaselineHunger:
              (seed['needsBaselineHunger'] as int?) ??
              source.frontPorchExtensions!.needsBaselineHunger,
          needsBaselineBladder:
              (seed['needsBaselineBladder'] as int?) ??
              source.frontPorchExtensions!.needsBaselineBladder,
          needsBaselineEnergy:
              (seed['needsBaselineEnergy'] as int?) ??
              source.frontPorchExtensions!.needsBaselineEnergy,
          needsBaselineSocial:
              (seed['needsBaselineSocial'] as int?) ??
              source.frontPorchExtensions!.needsBaselineSocial,
          needsBaselineFun:
              (seed['needsBaselineFun'] as int?) ??
              source.frontPorchExtensions!.needsBaselineFun,
          needsBaselineHygiene:
              (seed['needsBaselineHygiene'] as int?) ??
              source.frontPorchExtensions!.needsBaselineHygiene,
          needsBaselineComfort:
              (seed['needsBaselineComfort'] as int?) ??
              source.frontPorchExtensions!.needsBaselineComfort,
          needsDecayHunger:
              (seed['needsDecayHunger'] as int?) ??
              source.frontPorchExtensions!.needsDecayHunger,
          needsDecayBladder:
              (seed['needsDecayBladder'] as int?) ??
              source.frontPorchExtensions!.needsDecayBladder,
          needsDecayEnergy:
              (seed['needsDecayEnergy'] as int?) ??
              source.frontPorchExtensions!.needsDecayEnergy,
          needsDecaySocial:
              (seed['needsDecaySocial'] as int?) ??
              source.frontPorchExtensions!.needsDecaySocial,
          needsDecayFun:
              (seed['needsDecayFun'] as int?) ??
              source.frontPorchExtensions!.needsDecayFun,
          needsDecayHygiene:
              (seed['needsDecayHygiene'] as int?) ??
              source.frontPorchExtensions!.needsDecayHygiene,
          needsDecayComfort:
              (seed['needsDecayComfort'] as int?) ??
              source.frontPorchExtensions!.needsDecayComfort,
        );
      } else if (_realismEnabled) {
        memberFp = FrontPorchExtensions(
          enjoysLowHygiene: (seed['enjoysLowHygiene'] as bool?) ?? false,
          realismVerificationEnabled:
              (seed['verificationEnabled'] as bool?) ?? false,
          realismVerificationMaxReprocesses:
              (seed['verificationMaxReprocesses'] as int?) ?? 1,
          realismVerificationStrictness:
              (seed['verificationStrictness'] as int?) ?? 3,
          realismNeedsDirectorAuthority:
              (seed['needsDirectorAuthority'] as bool?) ?? false,
          needsBaselineHunger: (seed['needsBaselineHunger'] as int?) ?? 80,
          needsBaselineBladder: (seed['needsBaselineBladder'] as int?) ?? 80,
          needsBaselineEnergy: (seed['needsBaselineEnergy'] as int?) ?? 80,
          needsBaselineSocial: (seed['needsBaselineSocial'] as int?) ?? 80,
          needsBaselineFun: (seed['needsBaselineFun'] as int?) ?? 80,
          needsBaselineHygiene: (seed['needsBaselineHygiene'] as int?) ?? 80,
          needsBaselineComfort: (seed['needsBaselineComfort'] as int?) ?? 80,
          needsDecayHunger: (seed['needsDecayHunger'] as int?) ?? 5,
          needsDecayBladder: (seed['needsDecayBladder'] as int?) ?? 5,
          needsDecayEnergy: (seed['needsDecayEnergy'] as int?) ?? 5,
          needsDecaySocial: (seed['needsDecaySocial'] as int?) ?? 5,
          needsDecayFun: (seed['needsDecayFun'] as int?) ?? 5,
          needsDecayHygiene: (seed['needsDecayHygiene'] as int?) ?? 5,
          needsDecayComfort: (seed['needsDecayComfort'] as int?) ?? 5,
          needsSimStrength: (seed['needsSimStrength'] as int?) ?? 1,
        );
        memberFp.ensureStableId();
      }

      // Insert typed GroupMember row using the database instance.
      await database.insertGroupMember(
        db.GroupMembersCompanion(
          id: Value(mid),
          groupId: Value(groupId),
          name: Value(source.name),
          description: Value(source.description),
          personality: Value(source.personality),
          scenario: Value(source.scenario),
          firstMessage: Value(source.firstMessage),
          mesExample: Value(source.mesExample),
          systemPrompt: Value(source.systemPrompt),
          postHistoryInstructions: Value(source.postHistoryInstructions),
          alternateGreetings: Value(jsonEncode(source.alternateGreetings)),
          tags: Value(jsonEncode(source.tags)),
          avatarFilename: Value('$mid.png'),
          ttsVoice: Value(source.ttsVoice),
          lorebook: Value(
            source.lorebook != null
                ? jsonEncode(source.lorebook!.toJson())
                : null,
          ),
          worldNames: Value(jsonEncode(source.worldNames)),
          frontPorchExtensions: Value(
            memberFp != null
                ? jsonEncode(memberFp.toJson())
                : (source.frontPorchExtensions != null
                      ? jsonEncode(source.frontPorchExtensions!.toJson())
                      : null),
          ),
          rawExtensions: Value(
            source.rawExtensions != null
                ? jsonEncode(source.rawExtensions!)
                : null,
          ),
          // Provenance: stamp the source library character so this member can
          // later be traced back / collapsed to a 1:1 with the original.
          memberState: Value(
            GroupMember.encodeProvenance(
              originStableId: source.stableGroupId,
              originLibraryDbId: source.dbId,
            ),
          ),
        ),
      );
    }

    // Build the realism/needs/dynamics blobs from seeds re-keyed to member mids
    // (the ids the runtime reads). Done here — after the insert loop populated
    // memberIdMap — so the creator's per-member bond/trust/emotion/needs and
    // intragroup relationships actually take effect in chat.
    if (_realismEnabled) {
      final seeds = <String, Map<String, dynamic>>{
        for (final c in _members)
          _stableId(c):
              _memberRealismSeeds[_stableId(c)] ?? _defaultRealismSeedFor(c),
      };
      final blobs = buildGroupRealismBlobs(
        seeds: remapSeedsToMemberIds(seeds, memberIdMap),
        needsEnabled: _needsSimEnabled,
        timeOfDay: _globalTimeOfDay,
        dayCount: _globalDayCount,
        storyStartDate: _globalStoryStartDate,
        storyStartTime: _globalStoryStartTime,
        alternateGreetings: _altGreetings,
        greetingSeeds: _altGreetingSeeds,
      );
      defaultMemberJson = blobs.defaultMemberJson;
      baselineJson = blobs.baselineJson;
    }

    final group = GroupChat(
      id: groupId,
      name: name,
      // characterIds removed (clean break). Members persisted above to group_members + private avatars.
      turnOrder: _turnOrder,
      autoAdvance: _autoAdvance,
      directorMode: _directorMode,
      firstMessage: _firstMessageController.text.trim(),
      alternateGreetings: List.from(_altGreetings),
      greetingSeeds: List.from(_altGreetingSeeds),
      scenario: _scenarioController.text.trim(),
      systemPrompt: _groupSystemController.text.trim(),
      characterSystemPrompts: charPrompts,
      worldIds: List.from(_worldIds),
      groupLorebook: groupLoreJson,
      inheritCharacterLorebooks: _inheritCharacterLorebooks,
      chaosModeEnabled: _chaosModeEnabled,
      chaosNsfwEnabled: _chaosNsfwEnabled,
      baselineRealismState: baselineJson,
      defaultMemberRealismState: defaultMemberJson,
    );

    await groupRepo.save(group);

    // Apply voice overrides (same pattern as the old creator)
    for (final entry in _characterVoices.entries) {
      final card = _members.firstWhere(
        (c) => _stableId(c) == entry.key,
        orElse: () => _members.first,
      );
      if (entry.value.isNotEmpty && entry.value != card.ttsVoice) {
        card.ttsVoice = entry.value;
        // Library mutation intentionally skipped during group creation (private GroupMember rows
        // already captured the voice from source card at duplicate time; avoids subtle "library pollution"
        // side-effect per "never allow" + safety invariant. User can edit voice on the private group member later).
        // await repo.updateCharacter(card);  -- removed to prevent library side-effect
      }
    }

    if (enterChat) {
      // Full "Create & Enter" path.
      final chatService = Provider.of<ChatService>(context, listen: false);
      await chatService.setActiveGroup(group, groupRepo: groupRepo);
      await chatService.startNewChat();

      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const ChatPage()));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Group "$name" created!')));
      }
    } else {
      // "Create Only (don't enter chat yet)"
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(content: Text('Group "$name" created.')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            Icon(
              Icons.group_add,
              color: AppColors.resolve(
                context,
                AppColors.logLoading,
                AppColors.userBubble,
              ),
              size: 22,
            ),
            const SizedBox(width: 10),
            const Text('Create Group Chat'),
            const Spacer(),
            _buildStepIndicator(),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _tokenBadge(),
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _currentStep == 0
                ? _buildMembersStep()
                : _currentStep == 1
                ? _buildIdentityStep()
                : _currentStep == 2
                ? _buildPromptsStep()
                : _currentStep == 3
                ? _buildLoreStep()
                : _currentStep == 4
                ? _buildRealismStep()
                : _currentStep == 5
                ? (_members.length <= 4
                      ? _buildGroupDynamicsStep()
                      : _buildGroupDynamicsDisabledStep())
                : _currentStep == 6
                ? _buildOpeningStep()
                : _buildReviewStep(),
          ),
        ],
      ),
    );
  }
}
