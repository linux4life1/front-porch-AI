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
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/utils/character_id.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Value;
import 'package:front_porch_ai/database/database.dart' as db;

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
  final _scenarioController = TextEditingController();
  final _firstMessageController = TextEditingController();
  bool _isGeneratingScenario = false;
  bool _isGeneratingFirst = false;

  // Prompts
  final _groupSystemController = TextEditingController();
  final Map<String, String> _characterSystemPrompts = {}; // charId -> prompt

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

  // Global time/day for the whole group (not per-character — prevents footgun)
  String _globalTimeOfDay = 'morning';
  int _globalDayCount = 1;

  // Search / filter for Members browser
  final _memberSearchController = TextEditingController();
  String _memberSearchQuery = '';
  // (reserved for future folder filter chips in the Members browser)

  // Token-ish estimate (lightweight)
  int _contentTokenEstimate = 0;

  @override
  void initState() {
    super.initState();

    _nameController.addListener(_updateEstimates);
    _scenarioController.addListener(_updateEstimates);
    _firstMessageController.addListener(_updateEstimates);
    _groupSystemController.addListener(_updateEstimates);
    _memberSearchController.addListener(() {
      setState(
        () => _memberSearchQuery = _memberSearchController.text
            .trim()
            .toLowerCase(),
      );
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _groupSystemController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  void _updateEstimates() {
    int total = 0;
    total += (_nameController.text.length / 4).ceil();
    total += (_scenarioController.text.length / 4).ceil();
    total += (_firstMessageController.text.length / 4).ceil();
    total += (_groupSystemController.text.length / 4).ceil();
    for (final p in _characterSystemPrompts.values) {
      total += (p.length / 4).ceil();
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

  List<CharacterCard> get _filteredAvailable {
    final q = _memberSearchQuery;
    var list = _availableCharacters;
    if (q.isNotEmpty) {
      list = list
          .where(
            (c) =>
                c.name.toLowerCase().contains(q) ||
                c.description.toLowerCase().contains(q) ||
                c.personality.toLowerCase().contains(q),
          )
          .toList();
    }
    // Simple sort by name
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
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

  void _reorderMembers(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _members.removeAt(oldIndex);
      _members.insert(newIndex, moved);
    });
  }

  void _setVoice(String charId, String? voiceId) {
    setState(() {
      _characterVoices[charId] = voiceId ?? '';
    });
  }

  Map<String, dynamic> _defaultRealismSeedFor(CharacterCard c) {
    // Neutral but alive starting point
    return {
      'affection': 35,
      'trust': 40,
      'emotion': 'neutral',
      'emotionIntensity': 'mild',
      'timeOfDay': 'morning',
      'dayCount': 1,
      'needs': <String, int>{
        'hunger': 70,
        'thirst': 75,
        'rest': 65,
        'social': 60,
        'hygiene': 80,
        'bladder': 85,
      },
      'enjoysLowHygiene': false,
      'relationships':
          <String, int>{}, // seeded in Group Dynamics step for small groups
    };
  }

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
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final keyCtrl = TextEditingController(text: existing?.key ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');

    // Use StatefulBuilder so the toggles and slider update live inside the dialog.
    // The previous Row + Expanded + SwitchListTile pattern caused horrific wrapping
    // ("Enable d", "Consta nt") and the switches/slider never responded visually.
    bool enabled = existing?.enabled ?? true;
    bool constant = existing?.constant ?? false;
    int sticky = existing?.stickyDepth ?? 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          existing == null ? 'Add Group Lore Entry' : 'Edit Group Lore Entry',
        ),
        content: StatefulBuilder(
          builder: (innerCtx, setInnerState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Entry Name (optional)',
                    ),
                  ),
                  if (!constant) ...[
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: keyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Trigger Keys (comma or space separated)',
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: contentCtrl,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Content (injected when triggered)',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Clean, non-wrapping toggle section (replaces the broken SwitchListTile rows)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cardOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Enabled',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'This entry can be injected when its keys match',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: enabled,
                              onChanged: (v) =>
                                  setInnerState(() => enabled = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Divider(color: AppColors.borderOf(context), height: 1),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Constant',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Always considered active (ignores trigger keys)',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: constant,
                              onChanged: (v) =>
                                  setInnerState(() => constant = v),
                            ),
                          ],
                        ),
                        if (!constant) ...[
                          const SizedBox(height: 12),
                          Divider(
                            color: AppColors.borderOf(context),
                            height: 1,
                          ),
                          const SizedBox(height: 12),

                          // Sticky Depth — clean slider presentation
                          // (hidden when Constant is on, since constant entries never decay)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Sticky Depth',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.surfaceContainerOf(
                                        context,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$sticky',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary(context),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'How many turns the entry stays active after triggering',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: AppColors.resolve(
                                    context,
                                    Colors.tealAccent,
                                    Colors.teal.shade700,
                                  ),
                                  inactiveTrackColor: AppColors.borderOf(
                                    context,
                                  ).withValues(alpha: 0.4),
                                  thumbColor: AppColors.resolve(
                                    context,
                                    Colors.tealAccent,
                                    Colors.teal.shade700,
                                  ),
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                ),
                                child: Slider(
                                  value: sticky.toDouble().clamp(0, 12),
                                  min: 0,
                                  max: 12,
                                  divisions: 12,
                                  label: sticky.toString(),
                                  onChanged: (v) =>
                                      setInnerState(() => sticky = v.round()),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final entry = LorebookEntry(
      name: nameCtrl.text.trim(),
      key: keyCtrl.text.trim(),
      content: contentCtrl.text.trim(),
      enabled: enabled,
      constant: constant,
      stickyDepth: sticky,
    );

    setState(() {
      if (index != null && index >= 0 && index < _groupLoreEntries.length) {
        _groupLoreEntries[index] = entry;
      } else {
        _groupLoreEntries.add(entry);
      }
      _updateEstimates();
    });
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
        final tier = _getRelationshipTierName(value);
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

    // Build per-char system prompts & voices
    final charPrompts = <String, String>{};
    for (final c in _members) {
      final id = _stableId(c);
      final p = _characterSystemPrompts[id];
      if (p != null && p.trim().isNotEmpty) charPrompts[id] = p.trim();
    }

    // Serialize group lorebook
    final lb = Lorebook(entries: List.from(_groupLoreEntries));
    final groupLoreJson = jsonEncode(lb.toJson());

    // Build realism blobs (create-only path now).
    String baselineJson = '{}';
    String defaultMemberJson = '{}';

    if (_realismEnabled) {
      final defaultMember = <String, dynamic>{'perChar': <String, dynamic>{}};

      for (final c in _members) {
        final id = _stableId(c);
        var seed = _memberRealismSeeds[id] ?? _defaultRealismSeedFor(c);

        if (!_needsSimEnabled) {
          seed = Map<String, dynamic>.from(seed)..remove('needs');
        }

        (defaultMember['perChar'] as Map)[id] = seed;
      }

      defaultMemberJson = jsonEncode(defaultMember);

      final baseline = <String, dynamic>{};
      for (final c in _members) {
        final id = _stableId(c);
        var seed = _memberRealismSeeds[id] ?? _defaultRealismSeedFor(c);
        if (!_needsSimEnabled) {
          seed = Map<String, dynamic>.from(seed)..remove('needs');
        }
        baseline[id] = {
          'affection': (seed['affection'] as num?)?.toInt() ?? 35,
          'trust': (seed['trust'] as num?)?.toInt() ?? 40,
          'emotion': (seed['emotion'] as String?) ?? 'neutral',
          'emotionIntensity': (seed['emotionIntensity'] as String?) ?? 'mild',
          'timeOfDay': _globalTimeOfDay,
          'dayCount': _globalDayCount,
        };
      }
      baselineJson = jsonEncode(baseline);
    }

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
            source.frontPorchExtensions != null
                ? jsonEncode(source.frontPorchExtensions!.toJson())
                : null,
          ),
          rawExtensions: Value(
            source.rawExtensions != null
                ? jsonEncode(source.rawExtensions!)
                : null,
          ),
          memberState: const Value('{}'),
        ),
      );
    }

    final group = GroupChat(
      id: groupId,
      name: name,
      // characterIds removed (clean break). Members persisted above to group_members + private avatars.
      turnOrder: _turnOrder,
      autoAdvance: _autoAdvance,
      directorMode: _directorMode,
      firstMessage: _firstMessageController.text.trim(),
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

  Widget _buildMembersStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Members',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Build your roster. At least 2 characters required.',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 16),

          // Current Roster
          Row(
            children: [
              Text(
                'Current Roster (${_members.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              if (_members.length < 2) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.resolve(
                      context,
                      Colors.redAccent.withValues(alpha: 0.15),
                      Colors.red.withValues(alpha: 0.15),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Minimum 2 required',
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        Colors.redAccent,
                        Colors.red.shade700,
                      ),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('No members yet — add from the browser below'),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _members.length,
              onReorder: _reorderMembers,
              itemBuilder: (ctx, i) {
                final c = _members[i];
                final id = _stableId(c);
                final voice = _characterVoices[id] ?? c.ttsVoice ?? '';
                return Card(
                  key: ValueKey(id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _avatar(c, radius: 22),
                    title: Text(c.name),
                    subtitle: Text(
                      '${c.description.isNotEmpty ? c.description.substring(0, c.description.length.clamp(0, 60)) : "No description"}...',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _voiceDropdown(c, voice, (v) => _setVoice(id, v)),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => _removeMember(id),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 24),
          Text(
            'Add Characters',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 8),

          // Search
          TextField(
            controller: _memberSearchController,
            decoration: InputDecoration(
              hintText: 'Search available characters...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Available grid (compact)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filteredAvailable.map((c) {
              return InkWell(
                onTap: () => _addMember(c),
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Row(
                    children: [
                      _avatar(c, radius: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      Icon(
                        Icons.add,
                        size: 18,
                        color: AppColors.resolve(
                          context,
                          const Color(0xFF7C3AED),
                          const Color(0xFF6D28D9),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_filteredAvailable.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No more characters available.',
                style: TextStyle(color: AppColors.textTertiary(context)),
              ),
            ),

          _buildNavButtons(currentStep: 0),
        ],
      ),
    );
  }

  Widget _voiceDropdown(
    CharacterCard c,
    String current,
    ValueChanged<String?> onChanged,
  ) {
    final tts = Provider.of<TtsService>(context, listen: false);
    final voices = tts.activeVoices;
    return DropdownButton<String>(
      value: current.isNotEmpty ? current : null,
      hint: const Text('Voice'),
      isDense: true,
      items: [
        const DropdownMenuItem(value: '', child: Text('Default')),
        ...voices.map(
          (v) => DropdownMenuItem(
            value: v.id,
            child: Text(v.name, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _avatar(CharacterCard c, {double radius = 20}) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: c.imagePath != null
          ? FileImage(File(c.imagePath!))
          : null,
      child: c.imagePath == null
          ? Icon(Icons.person, size: radius * 0.9)
          : null,
    );
  }

  Widget _buildIdentityStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Identity & Behavior',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          AppTextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Group Name',
              hintText: 'e.g. The Ember Circle',
            ),
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Turn Order',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 8),
          SegmentedButton<TurnOrder>(
            segments: const [
              ButtonSegment(
                value: TurnOrder.roundRobin,
                label: Text('Round Robin'),
                icon: Icon(Icons.repeat),
              ),
              ButtonSegment(
                value: TurnOrder.random,
                label: Text('Random'),
                icon: Icon(Icons.shuffle),
              ),
            ],
            selected: {_turnOrder},
            onSelectionChanged: (v) => setState(() => _turnOrder = v.first),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Auto-Advance'),
            subtitle: const Text(
              'Characters respond one after another automatically',
            ),
            value: _autoAdvance,
            onChanged: (v) => setState(() => _autoAdvance = v),
            activeThumbColor: AppColors.resolve(
              context,
              const Color(0xFF7C3AED),
              const Color(0xFF6D28D9),
            ),
          ),
          SwitchListTile(
            title: Row(
              children: [
                Icon(
                  Icons.movie_creation,
                  color: AppColors.resolve(
                    context,
                    Colors.amberAccent,
                    Colors.amber.shade700,
                  ),
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text('Director Mode'),
              ],
            ),
            subtitle: const Text(
              'Characters chat autonomously — you direct the scene (no player present)',
            ),
            value: _directorMode,
            onChanged: (v) => setState(() => _directorMode = v),
            activeThumbColor: AppColors.resolve(
              context,
              Colors.amberAccent,
              Colors.amber.shade700,
            ),
          ),

          _buildNavButtons(currentStep: 1),
        ],
      ),
    );
  }

  Widget _buildOpeningStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Opening Scene',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Dialogue subsection (groups): first message + explicit coming-soon stub for alt greetings.
          // Completely omits Example Dialogue (CharacterCard / mes_example concept only; no such field on GroupChat).
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      color: AppColors.resolve(
                        context,
                        Colors.blueAccent,
                        Colors.blue.shade700,
                      ),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Dialogue',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.resolve(
                          context,
                          Colors.blueAccent,
                          Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'First Message (optional)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final dynamics = _buildDynamicsContextForGeneration();
                        await _generateFirstMessage(dynamicsContext: dynamics);
                      },
                      icon: _isGeneratingFirst
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.auto_awesome,
                              color: AppColors.resolve(
                                context,
                                Colors.amberAccent,
                                Colors.amber.shade700,
                              ),
                            ),
                      label: Text(
                        _isGeneratingFirst
                            ? 'Generating...'
                            : 'Generate with Dynamics',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _firstMessageController,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    hintText: 'The scene opens with...',
                  ),
                ),
                const SizedBox(height: 8),
                if (_directorMode)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.resolve(
                        context,
                        Colors.amber.withValues(alpha: 0.08),
                        Colors.amber.withValues(alpha: 0.08),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Director Mode: generated opening will be a self-contained group scene.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.resolve(
                          context,
                          Colors.amberAccent,
                          Colors.amber.shade700,
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 20),

                // Alternate Greetings stub (non-functional, informative only — groups do not support per-group alt greetings yet).
                Opacity(
                  opacity: 0.6,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.borderOf(
                          context,
                        ).withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.swap_horiz,
                              color: AppColors.iconSecondary(context),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Alternate Greetings',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.resolve(
                                  context,
                                  const Color(0xFF334155),
                                  const Color(0xFFE5E7EB),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Coming soon',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textTertiary(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Alternate greetings for groups are coming in a future update. The opening message above is used for new sessions today.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                  'Scenario (optional)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final dynamics = _buildDynamicsContextForGeneration();
                  await _generateScenario(dynamicsContext: dynamics);
                },
                icon: _isGeneratingScenario
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.auto_awesome,
                        color: AppColors.resolve(
                          context,
                          Colors.amberAccent,
                          Colors.amber.shade700,
                        ),
                      ),
                label: Text(
                  _isGeneratingScenario
                      ? 'Generating...'
                      : 'Generate with Dynamics',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _scenarioController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'The group is...'),
          ),

          _buildNavButtons(currentStep: 6),
        ],
      ),
    );
  }

  Widget _buildPromptsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Personality & World" subsection for groups (per spec): only group-applicable fields.
          // Omits Description/Personality (CharacterCard-only concepts). Scenario lives in Opening.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      color: AppColors.resolve(
                        context,
                        const Color(0xFF0EA5E9),
                        const Color(0xFF0284C8),
                      ),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Personality & World',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.resolve(
                          context,
                          const Color(0xFF0EA5E9),
                          const Color(0xFF0284C8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Group-level equivalents to character personality live in the system prompt and scenario.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Group System Prompt',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _groupSystemController,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Global instructions for this group...',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Per-Character Overrides (optional)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ..._members.map((c) {
            final id = _stableId(c);
            final ctrl = TextEditingController(
              text: _characterSystemPrompts[id] ?? '',
            );
            ctrl.addListener(() {
              _characterSystemPrompts[id] = ctrl.text;
            });
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _avatar(c, radius: 16),
                        const SizedBox(width: 8),
                        Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    AppTextField(
                      controller: ctrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        hintText:
                            'Extra instructions only for this character in this group',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          if (_members.isEmpty)
            const Text('Add members first to configure per-character prompts.'),

          _buildNavButtons(currentStep: 2),
        ],
      ),
    );
  }

  Widget _buildLoreStep() {
    final worldRepo = Provider.of<WorldRepository>(context);
    final allWorlds = worldRepo.worlds;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Group Lorebook',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showLoreEntryEditor(),
                icon: const Icon(Icons.add),
                label: const Text('Add Entry'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_groupLoreEntries.isEmpty)
            const Text(
              'No group lore entries yet. These take highest priority in prompts.',
            )
          else
            ..._groupLoreEntries.asMap().entries.map((e) {
              final i = e.key;
              final entry = e.value;
              return ListTile(
                title: Text(entry.name.isNotEmpty ? entry.name : entry.key),
                subtitle: Text(
                  entry.content.length > 80
                      ? '${entry.content.substring(0, 80)}...'
                      : entry.content,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () =>
                          _showLoreEntryEditor(existing: entry, index: i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _deleteLoreEntry(i),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Inherit character & world lorebooks'),
            subtitle: const Text(
              'When on, member cards and their attached worlds contribute lore in addition to the group lorebook above.',
            ),
            value: _inheritCharacterLorebooks,
            onChanged: (v) => setState(() => _inheritCharacterLorebooks = v),
          ),
          const SizedBox(height: 16),
          Text(
            'Linked Worlds',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ..._worldIds.map((wid) {
                final w = allWorlds.firstWhere(
                  (ww) => ww.name == wid,
                  orElse: () => World(
                    name: wid,
                    lorebook: Lorebook(entries: const []),
                  ),
                );
                return Chip(
                  label: Text(w.name),
                  onDeleted: () => _toggleWorld(wid),
                );
              }),
              OutlinedButton.icon(
                onPressed: () async {
                  final chosen = await showDialog<World>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Link a World'),
                      children: allWorlds
                          .map(
                            (w) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(ctx, w),
                              child: Text(w.name),
                            ),
                          )
                          .toList(),
                    ),
                  );
                  if (chosen != null) _toggleWorld(chosen.name);
                },
                icon: const Icon(Icons.public),
                label: const Text('Link World'),
              ),
            ],
          ),

          _buildNavButtons(currentStep: 3),
        ],
      ),
    );
  }

  Widget _buildRealismStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Chaos — styled nicely like the Realism card (independent of Realism)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.casino,
                      size: 18,
                      color: AppColors.resolve(
                        context,
                        const Color(0xFFFFD166),
                        const Color(0xFFB45309),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Group Chaos (Chance Time)',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Switch(
                      value: _chaosModeEnabled,
                      activeThumbColor: AppColors.resolve(
                        context,
                        const Color(0xFFFFD166),
                        const Color(0xFFB45309),
                      ),
                      onChanged: (v) => setState(() => _chaosModeEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Random narrative events during roleplay. Can include NSFW events when enabled.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                if (_chaosModeEnabled) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text(
                        'Include NSFW events',
                        style: TextStyle(fontSize: 13),
                      ),
                      const Spacer(),
                      Switch(
                        value: _chaosNsfwEnabled,
                        activeThumbColor: AppColors.resolve(
                          context,
                          const Color(0xFFFFD166),
                          const Color(0xFFB45309),
                        ),
                        onChanged: (v) => setState(() => _chaosNsfwEnabled = v),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // === Master Realism Toggle (the only on/off control for the whole group) ===
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: AppColors.resolve(
                        context,
                        Colors.tealAccent,
                        Colors.teal.shade700,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Realism Engine for this group',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Switch(
                      value: _realismEnabled,
                      activeThumbColor: AppColors.resolve(
                        context,
                        Colors.tealAccent,
                        Colors.teal.shade700,
                      ),
                      onChanged: (v) => setState(() => _realismEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Tracks emotions, short/long-term bond, trust, arousal, fixation, and needs simulation for every member. Only takes effect when not in Director Mode.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                if (!_realismEnabled)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'All realism features (bond, trust, emotion, needs, fixation, chaos pressure, etc.) are disabled for this group while the master toggle is off.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary(context),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                // Needs Simulation gated under Realism
                if (_realismEnabled) ...[
                  const SizedBox(height: 14),
                  Divider(color: AppColors.borderOf(context), height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.battery_std,
                        size: 18,
                        color: AppColors.resolve(
                          context,
                          Colors.tealAccent,
                          Colors.teal.shade700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Needs Simulation',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Switch(
                        value: _needsSimEnabled,
                        activeThumbColor: AppColors.resolve(
                          context,
                          Colors.tealAccent,
                          Colors.teal.shade700,
                        ),
                        onChanged: (v) => setState(() => _needsSimEnabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hunger, bladder, energy, social, fun, hygiene, comfort. Only relevant when Realism is enabled.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Global Time & Day (group level, not per-character)
          if (_realismEnabled) ...[
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: AppColors.resolve(
                    context,
                    Colors.amberAccent,
                    Colors.amber.shade700,
                  ),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Group Time & Day',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.resolve(
                      context,
                      Colors.amberAccent,
                      Colors.amber.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Time of Day',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        DropdownButton<String>(
                          value: _globalTimeOfDay,
                          isExpanded: true,
                          dropdownColor: AppColors.surfaceContainerOf(context),
                          onChanged: (v) =>
                              setState(() => _globalTimeOfDay = v!),
                          items: const [
                            DropdownMenuItem(
                              value: 'dawn',
                              child: Text('Dawn'),
                            ),
                            DropdownMenuItem(
                              value: 'morning',
                              child: Text('Morning'),
                            ),
                            DropdownMenuItem(
                              value: 'late_morning',
                              child: Text('Late Morning'),
                            ),
                            DropdownMenuItem(
                              value: 'afternoon',
                              child: Text('Afternoon'),
                            ),
                            DropdownMenuItem(
                              value: 'evening',
                              child: Text('Evening'),
                            ),
                            DropdownMenuItem(
                              value: 'night',
                              child: Text('Night'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Day Number',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: TextEditingController(
                            text: _globalDayCount.toString(),
                          ),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            if (n != null && n >= 1) {
                              setState(() => _globalDayCount = n);
                            }
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Per-member initial state configuration — only shown when realism is enabled for the group
          if (_realismEnabled) ...[
            Row(
              children: [
                Text(
                  'Initial Realism State per Member',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => _bulkSeedRealism('neutral'),
                  child: const Text('Neutral'),
                ),
                TextButton(
                  onPressed: () => _bulkSeedRealism('highBond'),
                  child: const Text('High Bond'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              const Text(
                'Add members first to configure their starting realism values.',
              )
            else
              ..._members.map((c) {
                final id = _stableId(c);
                final seed =
                    _memberRealismSeeds[id] ?? _defaultRealismSeedFor(c);
                return Card(
                  key: ValueKey('realism-card-$id'),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: _avatar(c, radius: 18),
                    title: Text(c.name),
                    subtitle: Text(
                      '${seed['emotion']} • Bond ${seed['affection']} / Trust ${seed['trust']}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: RealismFormSection(
                          key: ValueKey('realism-form-$id'),
                          enabled: true,
                          onEnabledChanged:
                              (
                                _,
                              ) {}, // controlled by the group master toggle above
                          timeOfDay:
                              (seed['timeOfDay'] as String?) ?? 'morning',
                          onTimeOfDayChanged: (v) =>
                              _updateMemberRealism(id, {'timeOfDay': v}),
                          dayCount: (seed['dayCount'] as num?)?.toInt() ?? 1,
                          onDayCountChanged: (v) =>
                              _updateMemberRealism(id, {'dayCount': v}),
                          shortTermBond:
                              (seed['affection'] as num?)?.toInt() ?? 35,
                          onShortTermBondChanged: (v) =>
                              _updateMemberRealism(id, {'affection': v}),
                          longTermBond: (seed['trust'] as num?)?.toInt() ?? 40,
                          onLongTermBondChanged: (v) =>
                              _updateMemberRealism(id, {'trust': v}),
                          trustLevel: (seed['trust'] as num?)?.toInt() ?? 40,
                          onTrustLevelChanged: (v) =>
                              _updateMemberRealism(id, {'trust': v}),
                          emotion: (seed['emotion'] as String?) ?? 'neutral',
                          onEmotionChanged: (v) =>
                              _updateMemberRealism(id, {'emotion': v}),
                          emotionIntensity:
                              (seed['emotionIntensity'] as String?) ?? 'mild',
                          onEmotionIntensityChanged: (v) =>
                              _updateMemberRealism(id, {'emotionIntensity': v}),
                          // These are group-level concepts (we already have the master Chaos toggle at the top of the section).
                          // Forcing them off here prevents duplicate/confusing per-character toggles.
                          nsfwCooldownEnabled: false,
                          onNsfwCooldownChanged: (_) {},
                          chaosModeEnabled: false,
                          onChaosModeChanged: (_) {},
                          needsSimEnabled: _needsSimEnabled,
                          onNeedsSimChanged: (_) {},
                          // When global Needs is on, this lets the widget show "Enjoys low hygiene"
                          // under Optional Features even though we hide the Needs master row itself.
                          // Hide the global-only toggles entirely from per-character optional features.
                          showNsfwCooldownToggle: false,
                          showChaosToggle: false,
                          showNeedsToggle: false,
                          showTimeAndDay: false,
                          showMasterEnabledToggle: false,
                          // Enjoys low hygiene will now naturally appear under Optional Features
                          // when the global Needs Simulation is enabled (because needsSimEnabled is passed above).
                          enjoysLowHygiene:
                              (seed['enjoysLowHygiene'] as bool?) ?? false,
                          onEnjoysLowHygieneChanged: (v) =>
                              _updateMemberRealism(id, {'enjoysLowHygiene': v}),
                          currentTask: (seed['currentTask'] as String?) ?? '',
                          onCurrentTaskChanged: (v) =>
                              _updateMemberRealism(id, {'currentTask': v}),
                        ),
                      ),

                      TextButton(
                        onPressed: () => _seedRealismFromCard(id),
                        child: const Text('Reset to character defaults'),
                      ),
                    ],
                  ),
                );
              }),
          ] else ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.cardOf(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Realism is disabled for this group. No bond, trust, emotion, needs, or fixation tracking will occur.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ),
          ],

          _buildNavButtons(currentStep: 4),
        ],
      ),
    );
  }

  // ── Group Dynamics (Intra-group relationships) ──────────────────────

  Widget _buildGroupDynamicsDisabledStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_alt,
              size: 64,
              color: AppColors.textTertiary(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Group Dynamics',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Intra-group relationship seeding is only available for groups with 4 or fewer members.\n\n'
              'Your current group has ${_members.length} members.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
            const SizedBox(height: 24),
            Text(
              'Larger groups use different social dynamics modeling.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupDynamicsStep() {
    // This should only be called when _members.length <= 4
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Group Dynamics',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message:
                    'Pre-seed hidden intra-group relationship scores (same -300..+300 raw scale as Long-Term Bond in Realism). Only available for groups of 4 or fewer per engine limits. These private feelings (never shown in UI) influence how members treat each other in prompts and behavior when the Realism Engine is active. Values persist in the Group Card export and round-trip on split-to-solo.',
                preferBelow: false,
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pre-seed how the characters feel toward each other. These hidden relationships influence behavior in small groups (4 or fewer members).',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
          const SizedBox(height: 24),

          ..._members.map((source) {
            final sourceId = _stableId(source);
            final relationships =
                (_memberRealismSeeds[sourceId]?['relationships'] as Map?)
                    ?.cast<String, int>() ??
                {};

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _avatar(source, radius: 20),
                        const SizedBox(width: 12),
                        Text(
                          'How ${source.name} feels about others',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    ..._members.where((target) => _stableId(target) != sourceId).map((
                      target,
                    ) {
                      final targetId = _stableId(target);
                      final currentValue = relationships[targetId] ?? 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _avatar(target, radius: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text(target.name)),
                                Tooltip(
                                  message:
                                      'Hidden relationship score on the same -300..+300 scale as Long-Term Bond. Positive values mean the source character privately feels warmly toward the target.',
                                  child: Text(
                                    currentValue > 0
                                        ? '+$currentValue'
                                        : currentValue.toString(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: _getRelationshipColor(
                                        currentValue,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: _getRelationshipColor(
                                  currentValue,
                                ),
                                inactiveTrackColor: AppColors.borderOf(
                                  context,
                                ).withValues(alpha: 0.3),
                                thumbColor: _getRelationshipColor(currentValue),
                                trackHeight: 4,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8,
                                ),
                              ),
                              child: Slider(
                                value: currentValue.toDouble().clamp(-300, 300),
                                min: -300,
                                max: 300,
                                divisions: 120,
                                label: currentValue.toString(),
                                onChanged: (v) {
                                  _updateRelationship(
                                    sourceId,
                                    targetId,
                                    v.round(),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 4),
                            Tooltip(
                              message:
                                  'Starting hidden feeling of ${source.name} toward ${target.name}. Matches the Long-Term Bond tier system used in the 1:1 Realism creator and runtime evaluations. These scores only affect groups of 4 or fewer and drive realistic intra-group behavior when Realism is enabled.',
                              child: Text(
                                _getRelationshipTierName(currentValue),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _getRelationshipColor(currentValue),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
          Text(
            'These values are private to the group and affect how characters treat each other when Realism is active.',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 12,
            ),
          ),

          _buildNavButtons(currentStep: 5),
        ],
      ),
    );
  }

  void _updateRelationship(String fromId, String toId, int value) {
    setState(() {
      final seed = _memberRealismSeeds[fromId] ??= _defaultRealismSeedFor(
        _members.firstWhere((c) => _stableId(c) == fromId),
      );

      final rels =
          (seed['relationships'] as Map<String, int>?)?.cast<String, int>() ??
          {};
      rels[toId] = value;
      seed['relationships'] = rels;
    });
  }

  // ── Group Dynamics Helpers ──────────────────────────────────────────

  String _getRelationshipTierName(int value) {
    // Aligned with Long-Term Bond tiers from RealismFormSection and chat_service longTermTierName semantics (raw -300..+300 scale).
    if (value >= 80) return 'Soulbound';
    if (value >= 50) return 'Deep Bond';
    if (value >= 20) return 'Close';
    if (value >= 5) return 'Familiar';
    if (value >= -4) return 'Acquaintance';
    if (value >= -19) return 'Uneasy';
    if (value >= -49) return 'Estranged';
    if (value >= -79) return 'Broken';
    return 'Nemesis';
  }

  Color _getRelationshipColor(int value) {
    // Granular valence coloring (green=positive, red=negative) for visual feedback.
    // Thresholds kept close to tier boundaries for consistency with existing bond/trust color logic.
    if (value >= 80) {
      return AppColors.resolve(
        context,
        Colors.greenAccent.shade200,
        Colors.green.shade200,
      );
    } else if (value >= 50) {
      return AppColors.resolve(
        context,
        Colors.greenAccent.shade400,
        Colors.green.shade400,
      );
    } else if (value >= 20) {
      return AppColors.resolve(
        context,
        Colors.greenAccent.shade700,
        Colors.green.shade700,
      );
    } else if (value >= 5) {
      return AppColors.resolve(context, Colors.lightGreen, Colors.lightGreen);
    } else if (value >= -4) {
      return AppColors.textSecondary(context);
    } else if (value >= -19) {
      return AppColors.resolve(
        context,
        Colors.orangeAccent,
        Colors.orange.shade700,
      );
    } else if (value >= -49) {
      return AppColors.resolve(
        context,
        Colors.deepOrangeAccent,
        Colors.deepOrange.shade700,
      );
    } else if (value >= -79) {
      return AppColors.resolve(context, Colors.redAccent, Colors.red.shade700);
    } else {
      return AppColors.resolve(
        context,
        Colors.red.shade700,
        Colors.red.shade900,
      );
    }
  }

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review & Opening',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // Scenario + First Message moved here (last step) so AI generation
          // can use the hidden relationships from the Group Dynamics step.
          Row(
            children: [
              Expanded(
                child: Text(
                  'Scenario (optional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final dynamics = _buildDynamicsContextForGeneration();
                  await _generateScenario(dynamicsContext: dynamics);
                },
                icon: _isGeneratingScenario
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.auto_awesome,
                        color: AppColors.resolve(
                          context,
                          Colors.amberAccent,
                          Colors.amber.shade700,
                        ),
                      ),
                label: Text(
                  _isGeneratingScenario
                      ? 'Generating...'
                      : 'Generate with Dynamics',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _scenarioController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'The group is...'),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Text(
                  'First Message (optional)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final dynamics = _buildDynamicsContextForGeneration();
                  await _generateFirstMessage(dynamicsContext: dynamics);
                },
                icon: _isGeneratingFirst
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.auto_awesome,
                        color: AppColors.resolve(
                          context,
                          Colors.amberAccent,
                          Colors.amber.shade700,
                        ),
                      ),
                label: Text(
                  _isGeneratingFirst
                      ? 'Generating...'
                      : 'Generate with Dynamics',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: _firstMessageController,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'The scene opens with...',
            ),
          ),
          const SizedBox(height: 8),
          if (_directorMode)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.resolve(
                  context,
                  Colors.amber.withValues(alpha: 0.08),
                  Colors.amber.withValues(alpha: 0.08),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Director Mode: generated opening will be a self-contained group scene.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.resolve(
                    context,
                    Colors.amberAccent,
                    Colors.amber.shade700,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Single group summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameController.text.isEmpty
                      ? 'Unnamed Group'
                      : _nameController.text,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: _members
                      .map((c) => Chip(label: Text(c.name)))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  '${_members.length} members • ${_groupLoreEntries.length} lore entries • ${_worldIds.length} worlds',
                ),
                if (_chaosModeEnabled)
                  Text(
                    'Chaos Mode enabled',
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        const Color(0xFFFFD166),
                        const Color(0xFFB45309),
                      ),
                    ),
                  ),
                if (_directorMode)
                  Text(
                    'Director Mode',
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        Colors.amberAccent,
                        Colors.amber.shade700,
                      ),
                    ),
                  ),
                Text(
                  _realismEnabled
                      ? 'Realism Engine: Enabled for group'
                      : 'Realism Engine: Disabled for group',
                  style: TextStyle(
                    color: _realismEnabled
                        ? AppColors.resolve(
                            context,
                            Colors.tealAccent,
                            Colors.teal.shade700,
                          )
                        : AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: () => _createGroup(enterChat: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.resolve(
                context,
                const Color(0xFF7C3AED),
                const Color(0xFF6D28D9),
              ),
              minimumSize: const Size.fromHeight(52),
            ),
            icon: const Icon(Icons.check),
            label: const Text(
              'Create Group & Enter Chat',
              style: TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _createGroup(enterChat: false),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Create Only (don\'t enter chat yet)'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP INDICATOR (matches Manual Character Creator style)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStepIndicator() {
    final labels = [
      'Members',
      'Identity',
      'Prompts',
      'Lore',
      'Realism',
      'Group Dynamics',
      'Opening',
      'Review',
    ];

    final children = <Widget>[];
    for (int i = 0; i < labels.length; i++) {
      final isDynamicsStep = (i == 6);
      final isAvailable = !isDynamicsStep || _members.length <= 4;

      children.add(_stepDot(i, labels[i], available: isAvailable));
      if (i < labels.length - 1) {
        children.add(_stepLine());
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _stepDot(int step, String label, {bool available = true}) {
    final isActive = available && _currentStep >= step;
    final isCurrent = _currentStep == step;

    final dotColor = !available
        ? AppColors.surfaceContainerOf(context).withValues(alpha: 0.5)
        : (isActive
              ? AppColors.resolve(
                  context,
                  const Color(0xFF7C3AED),
                  const Color(0xFF6D28D9),
                )
              : AppColors.surfaceContainerOf(context));

    final borderColor = isCurrent
        ? AppColors.textPrimary(context)
        : AppColors.borderOf(context);

    final numberOrCheckColor = isActive
        ? Colors.white
        : AppColors.textTertiary(context);

    final labelColor = !available
        ? AppColors.textTertiary(context).withValues(alpha: 0.6)
        : (isActive
              ? AppColors.textSecondary(context)
              : AppColors.textTertiary(context));

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: isCurrent
                ? Border.all(color: borderColor, width: 2)
                : Border.all(
                    color: AppColors.borderOf(context).withValues(alpha: 0.3),
                  ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '${step + 1}',
                    style: TextStyle(fontSize: 11, color: numberOrCheckColor),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
      ],
    );
  }

  Widget _stepLine() {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  NAVIGATION BUTTONS (matches Manual Character Creator)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavButtons({required int currentStep}) {
    final effectiveNextStep = _getEffectiveNextStep(currentStep);
    final isLastStep = effectiveNextStep == null;

    String nextText;
    if (isLastStep) {
      nextText = 'Create Group';
    } else if (effectiveNextStep == 6 && _members.length > 4) {
      nextText = 'Skip to Review';
    } else {
      nextText = 'Next';
    }

    final canGoNext = _canAdvanceFromStep(currentStep);

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentStep > 0)
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => _goToPreviousStep(currentStep),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (currentStep > 0) const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: canGoNext
                    ? () {
                        if (currentStep == 0 && !_canLeaveMembersStep) {
                          _showSnack('A group needs at least 2 characters.');
                          return;
                        }
                        if (isLastStep) {
                          _createGroup(); // defaults to enterChat: true (primary action)
                        } else {
                          setState(() => _currentStep = effectiveNextStep);
                        }
                      }
                    : null,
                icon: Icon(
                  isLastStep ? Icons.check : Icons.arrow_forward,
                  size: 20,
                ),
                label: Text(nextText, style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.resolve(
                    context,
                    const Color(0xFF7C3AED),
                    const Color(0xFF6D28D9),
                  ),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: AppColors.borderOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvanceFromStep(int step) {
    if (step == 0) return _canLeaveMembersStep;
    if (step == 6) {
      return _members.length >= 2 && _nameController.text.trim().isNotEmpty;
    }
    return true;
  }

  Widget _tokenBadge() {
    final color = _contentTokenEstimate > 6000
        ? AppColors.resolve(context, Colors.redAccent, Colors.red.shade700)
        : _contentTokenEstimate > 3000
        ? AppColors.resolve(
            context,
            Colors.orangeAccent,
            Colors.orange.shade700,
          )
        : AppColors.textTertiary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '~$_contentTokenEstimate tokens',
        style: TextStyle(color: color, fontSize: 12),
      ),
    );
  }
}
