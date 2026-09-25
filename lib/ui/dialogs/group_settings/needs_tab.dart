// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings_support.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_ext_persist.dart';

part 'needs_tab.member.dart';

const _kHunger = 'hunger';
const _kBladder = 'bladder';
const _kEnergy = 'energy';
const _kSocial = 'social';
const _kFun = 'fun';
const _kHygiene = 'hygiene';
const _kComfort = 'comfort';

const _needFields = [
  _kHunger,
  _kBladder,
  _kEnergy,
  _kSocial,
  _kFun,
  _kHygiene,
  _kComfort,
];

class GroupNeedsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const GroupNeedsTab({super.key, required this.chatService, this.groupRepo});

  @override
  State<GroupNeedsTab> createState() => _GroupNeedsTabState();
}

class _GroupNeedsTabState extends State<GroupNeedsTab> {
  bool _needsSimEnabled = false;

  // Per-character needs baselines: char-id → field-name → value
  final Map<String, Map<String, int>> _needsBaselines = {};

  // Pace (sloth/normal/fast) and which needs are off — same card-ext contract
  // as 1:1 editors. Wear follows the clock; there is no per-turn tick here.
  final Map<String, String> _needsPace = {};
  final Map<String, List<String>> _needsOff = {};

  // Per-character static preference overrides (e.g. enjoys low hygiene) for this group.
  final Map<String, bool> _enjoysLowHygiene = {};

  List<CharacterCard> _chars = [];

  // Baselines and "enjoys low hygiene" live on the member's card ext, which
  // only reaches disk through this persister — the dialog's Save writes the
  // groups row alone, so these edits used to vanish on the next launch.
  late final GroupMemberExtPersister _extPersister = GroupMemberExtPersister(
    widget.chatService,
  );

  // Field name constants for needs baselines map keys.

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceChanged);
    _initializeFromService();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _initializeFromService() {
    final cs = widget.chatService;
    _chars = cs.groupCharacters;

    _needsSimEnabled = cs.needsSimEnabled;

    for (final c in _chars) {
      final id = _getCharId(c);
      final ext = c.frontPorchExtensions;

      // Seed needs baselines from character card extensions.
      _needsBaselines[id] = {
        _kHunger: ext?.needsBaselineHunger ?? 80,
        _kBladder: ext?.needsBaselineBladder ?? 80,
        _kEnergy: ext?.needsBaselineEnergy ?? 80,
        _kSocial: ext?.needsBaselineSocial ?? 80,
        _kFun: ext?.needsBaselineFun ?? 80,
        _kHygiene: ext?.needsBaselineHygiene ?? 80,
        _kComfort: ext?.needsBaselineComfort ?? 80,
      };

      _enjoysLowHygiene[id] = ext?.enjoysLowHygiene ?? false;
      _needsPace[id] = ext?.needsPace ?? 'normal';
      _needsOff[id] = List<String>.from(ext?.needsOff ?? const []);
    }
  }

  // Must match ChatService._getCharacterIdFromCard / groupMemberStoreId.
  String _getCharId(CharacterCard c) => groupMemberStoreId(c);

  CharacterCard? _findCharById(String id) {
    for (final c in _chars) {
      if (_getCharId(c) == id) return c;
    }
    return null;
  }

  void _updateNeedsBaseline(String id, String field, int value) {
    setState(() {
      _needsBaselines[id] = {...?_needsBaselines[id], field: value};
      final char = _findCharById(id);
      if (char != null) {
        char.frontPorchExtensions =
            (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
              needsBaselineHunger: _needsBaselines[id]?[_kHunger] ?? 80,
              needsBaselineBladder: _needsBaselines[id]?[_kBladder] ?? 80,
              needsBaselineEnergy: _needsBaselines[id]?[_kEnergy] ?? 80,
              needsBaselineSocial: _needsBaselines[id]?[_kSocial] ?? 80,
              needsBaselineFun: _needsBaselines[id]?[_kFun] ?? 80,
              needsBaselineHygiene: _needsBaselines[id]?[_kHygiene] ?? 80,
              needsBaselineComfort: _needsBaselines[id]?[_kComfort] ?? 80,
            );
        char.frontPorchExtensions?.ensureStableId();
        _extPersister.schedule(char);
      }
    });
    // The card's needsBaseline* fields above are the real storage. A second
    // copy used to be written into the group blob under a 'needsBaselines'
    // key that nothing in lib/ or web_ui/ ever read back.
  }

  void _updateMemberEnjoysLowHygiene(CharacterCard char, bool value) {
    final id = _getCharId(char);
    setState(() {
      _enjoysLowHygiene[id] = value;
      char.frontPorchExtensions =
          (char.frontPorchExtensions ?? FrontPorchExtensions()).copyWith(
            enjoysLowHygiene: value,
          );
      char.frontPorchExtensions?.ensureStableId();
    });
    persistGroupMemberPref(widget.chatService, id, 'enjoysLowHygiene', value);
    // The blob key above is creation-time seeding only; the runtime reads
    // frontPorchExtensions.enjoysLowHygiene, so the card has to be written.
    _extPersister.schedule(char);
  }

  void _writeMemberExt(
    String id,
    FrontPorchExtensions Function(FrontPorchExtensions) patch,
  ) {
    final char = _findCharById(id);
    if (char == null) return;
    char.frontPorchExtensions = patch(
      char.frontPorchExtensions ?? FrontPorchExtensions(),
    );
    char.frontPorchExtensions?.ensureStableId();
    _extPersister.schedule(char);
  }

  void _updateNeedsPace(String id, String value) {
    setState(() {
      _needsPace[id] = value;
      _writeMemberExt(id, (ext) => ext.copyWith(needsPace: value));
    });
  }

  void _updateNeedsOff(String id, List<String> value) {
    setState(() {
      _needsOff[id] = List<String>.from(value);
      _writeMemberExt(
        id,
        (ext) => ext.copyWith(needsOff: List<String>.from(value)),
      );
    });
  }

  Future<void> _resetAllNeedsStates() async {
    for (final c in _chars) {
      await _resetCharacterNeeds(c);
    }
  }

  /// Put one member back on the engine defaults.
  ///
  /// Every value goes out through the SAME setters the sliders use. Resetting
  /// only the local maps repainted the dialog while the member kept its old
  /// pace / on-off / baselines — the card ext is what the runtime reads, and
  /// `resetRealismForGroupCharacter` only drops the live `_groupRealism` slot,
  /// it never touches the card.
  Future<void> _resetCharacterNeeds(CharacterCard character) async {
    final id = _getCharId(character);
    _updateNeedsPace(id, 'normal');
    _updateNeedsOff(id, const []);
    for (final field in _needFields) {
      _updateNeedsBaseline(id, field, 80);
    }
    _updateMemberEnjoysLowHygiene(character, false);
    widget.chatService.resetRealismForGroupCharacter(character);
    await _extPersister.flushMember(id);
    await widget.chatService.persistGroupMemberExtensions(memberId: id);
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);
    _extPersister.dispose();
    super.dispose();
  }

  void _updateNeedsSim(bool value) {
    setState(() {
      _needsSimEnabled = value;
    });
    widget.chatService.setNeedsSimEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final group = cs.activeGroup;
    final isDirectorMode = cs.observerMode;

    if (group == null) {
      return Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.battery_std, color: Colors.tealAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Needs — ${group.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Starting values, Pace, and which needs are on for Needs Simulation in this group. Wear follows the clock.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 12),

            // Director Mode notice
            if (isDirectorMode)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Director Mode is active. Needs Simulation is suspended for this group (narrative control only). Exit Director Mode to re-enable.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Needs Simulation master toggle
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.battery_std,
                        size: 18,
                        color: Colors.tealAccent,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Needs Simulation',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Switch(
                        value: _needsSimEnabled,
                        activeThumbColor: Colors.tealAccent,
                        onChanged: _updateNeedsSim,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Simulates need satisfaction (hunger, bladder, energy, social, fun, hygiene, comfort). Higher = more sated (100=full, 0=critical). Low values influence AI behavior and prompt injections.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Per-character starting values, Pace, and per-need on/off
            Row(
              children: [
                const Icon(
                  Icons.people_alt,
                  size: 18,
                  color: Colors.tealAccent,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Per-Character Needs',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _resetAllNeedsStates,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Reset ALL',
                    style: TextStyle(fontSize: 11, color: Colors.tealAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Starting values, Pace (Sloth / Normal / Fast), and which needs are on. Wear follows the clock, not a per-send tick. Each member has their own Pace.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 10),

            if (_chars.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No characters loaded for this group.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              )
            else
              ..._chars.asMap().entries.map(_buildMemberNeedsCard),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
