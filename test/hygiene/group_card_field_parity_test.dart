// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// GROUP CARD FIELD PARITY. A group member is the group's own copy of a
// character: its group_members row holds a whole card and its own Front
// Porch extensions. A field the 1:1 editor sets and a 1:1 chat reads has to
// be editable on the member (the member editor, desktop and phone) and read
// per member when a group turn runs, or it ships 1:1-only. An audit found
// such fields; this ratchet keeps a new one from shipping that way.
//
// The fields are read from the code, never typed here: every field
// FrontPorchExtensions declares, every key encodeFrontPorchExtensions
// writes, and every key CharacterCard.toJson writes. Each has an entry below
// that names where a member's value is edited and where a group reads it,
// or says why the group's own switch owns it (groupWide), why nothing reads
// it at chat time in 1:1 either (notRead), or why only a 1:1-only feature
// reads it (soloOnly). Each named place must still name the field.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_ratchet.dart';

const _extModel = 'lib/models/character/front_porch_extensions.dart';
const _extCodec = 'lib/models/character/front_porch_extensions_codec.dart';
const _cardModel = 'lib/models/character_card.dart';

/// The one CharacterCard.toJson key that is a container: its content is the
/// extensions, enumerated field by field from their own model and codec.
const _cardContainers = {'extensions'};

/// A place that edits or reads a field: [path] names [marker] in its code
/// (comments and strings blanked for Dart; TypeScript is read as text). `@`
/// in [marker] stands for the field's accessor.
class _At {
  const _At(this.path, [this.marker = '.@']);
  final String path;
  final String marker;
}

/// How a group member gets a field. A field a group reads per member lists
/// its [reader]s and its [editor]s (or why it has none, [noEditor]). The
/// others say who owns it instead: [groupWide], [notRead] or [soloOnly];
/// their [editor]s, when listed, are checked too.
class _Field {
  const _Field({
    this.editor = const [],
    this.reader = const [],
    this.noEditor,
    this.groupWide,
    this.notRead,
    this.soloOnly,
  });

  final List<_At> editor;
  final List<_At> reader;
  final String? noEditor;

  /// The group's own switch owns it at chat time; the member's copy is not
  /// read in a group.
  final String? groupWide;

  /// Read nowhere at chat time, in 1:1 either.
  final String? notRead;

  /// Read only by a feature groups do not have.
  final String? soloOnly;
}

// ── Where a member is edited ─────────────────────────────────────────────
// Desktop: the Edit Character page, opened on the member (Edit group, the
// chat sidebar) and saved to its row. Phone: CharacterEditPage at the
// member's route, through the relay's GroupMemberEdit. See _spine.
const _realismTab =
    'lib/ui/pages/edit_character_page/edit_character_realism_section.dart';
const _detailsTab =
    'lib/ui/pages/edit_character_page/edit_character_details_tab.dart';
const _dialogueTab =
    'lib/ui/pages/edit_character_page/edit_character_dialogue_tab.dart';
const _editPage = 'lib/ui/pages/edit_character_page.dart';
const _webRealism = 'web_ui/src/components/realism/RealismFormSection.tsx';
const _webNeeds = 'web_ui/src/components/realism/NeedsFormSection.tsx';
const _webStart = 'web_ui/src/components/realism/memberGroup.tsx';
const _webPage = 'web_ui/src/pages/CharacterEditPage.tsx';

/// The phone's Realism fields land on the card through the relay; a field
/// missing from it is dropped on every phone save.
const _relay = _At('lib/services/web/util/realism_extensions_json.dart', 'b.@');
const _relayCard = _At(
  'lib/services/web/facade/character/character_card_edits.dart',
  'card.@',
);

/// The member's row: the columns a member's card saves to.
const _rowPath = 'lib/services/group_member_card_save.dart';
const _row = _At(_rowPath, 'card.@');
const _webSet = _At(_webRealism, 'set({ @');
const _webNeedsSet = _At(_webNeeds, 'set({ @');
const _webPost = _At(_webPage, '@: c.@');

// ── Where a group turn reads a member ────────────────────────────────────
const _blocks = 'lib/services/chat/chat_service_generation_blocks.dart';
const _judges = 'lib/services/chat/chat_service_wiring_evals_judges.dart';
const _seed = 'lib/utils/group_member_card_seed.dart';
const _work = 'lib/services/chat/presence_derive.dart';
const _wear = 'lib/services/chat/needs_beat_wear.dart';
const _baselines = 'lib/services/chat/needs_simulation.dart';
const _prefs = 'lib/services/chat/prompt_injection/preferences_injection.dart';
const _afterglow = 'lib/services/chat/afterglow_pass.dart';
const _pockets = 'lib/services/chat/pockets_ledger.dart';
const _lore = 'lib/services/chat/lorebook_collection.dart';
const _greeting = 'lib/services/chat/chat_service_greeting.dart';

/// Bubble colours and font: the chat resolves them from the card of the
/// member who wrote the message.
const _bubbleCard = _At(
  'lib/ui/pages/chat_page_overlays.dart',
  'resolveGroupSpeakerForMessage',
);
const _uiSettings = 'lib/services/storage/settings/ui_settings.dart';
const _colorSlot = 'lib/ui/dialogs/ui_settings/chat_color_slot.dart';

const _extFields = <String, _Field>{
  'realismEnabled': _Field(
    groupWide:
        "the group chat's own Realism switch, behind Porch Life's; the "
        'member editor shows it read-only',
  ),
  // A member's start is the group's seed for them, set from the member
  // editor; their card's bonds and mood make the first seed only.
  'shortTermBond': _Field(
    editor: [
      _At(_realismTab, 's.copyWith(shortTerm'),
      _At(_webStart, 'set({ shortTermBond'),
    ],
    reader: [_At(_seed, 'e.shortTermBond')],
  ),
  'longTermBond': _Field(
    editor: [
      _At(_realismTab, 's.copyWith(longTerm'),
      _At(_webStart, 'set({ longTermBond'),
    ],
    reader: [_At(_seed, 'e.longTermBond')],
  ),
  'trustLevel': _Field(
    editor: [
      _At(_realismTab, 's.copyWith(trust'),
      _At(_webStart, 'set({ trustLevel'),
    ],
    reader: [_At(_seed, 'e.trustLevel')],
  ),
  'characterEmotion': _Field(
    editor: [
      _At(_realismTab, 's.copyWith(emotion'),
      _At(_webStart, 'set({ characterEmotion'),
    ],
    reader: [
      _At(_seed, 'e.characterEmotion'),
      _At('lib/services/chat/long_skip_settle.dart', 'cardExt?.@'),
    ],
  ),
  'emotionIntensity': _Field(
    editor: [
      _At(_realismTab, 's.copyWith(emotionIntensity'),
      _At(_webStart, 'set({ emotionIntensity'),
    ],
    reader: [
      _At(_seed, 'e.emotionIntensity'),
      _At('lib/services/chat/long_skip_settle.dart', 'cardExt?.@'),
    ],
  ),
  'dayCount': _Field(groupWide: "the group's one clock for the scene"),
  'timeOfDay': _Field(groupWide: "the group's one clock for the scene"),
  'storyStartDate': _Field(
    groupWide: "the group's own story calendar seeds its one clock",
  ),
  'storyStartTime': _Field(
    groupWide: "the group's own story calendar seeds its one clock",
  ),
  'nsfwCooldownEnabled': _Field(
    soloOnly:
        "the card's old Afterglow flag: chats start Afterglow from "
        "afterglowEnabled. Only a 1:1 Scene Guest mint reads the host's "
        'flag, and groups add members, not Scene Guests',
  ),
  'passageOfTimeEnabled': _Field(
    notRead: "the clock follows Porch Life's Passage of Time, read live",
  ),
  'chaosModeEnabled': _Field(
    groupWide: "the group's own Chaos switch, OR'd with Porch Life's default",
  ),
  'needsSimChoice': _Field(
    groupWide:
        "the group chat's Needs switch, behind NeedsPass.active; the member "
        'editor shows it read-only',
  ),
  'pocketsEnabled': _Field(
    editor: [_At(_detailsTab, 'd.realismPocketsEnabled'), _webSet, _relay],
    reader: [_At(_pockets, 'ext.@')],
  ),
  'afterglowEnabled': _Field(
    editor: [_At(_realismTab, 'd.realismAfterglow'), _webSet, _relay],
    reader: [_At('lib/services/chat/group_realism_store.dart')],
  ),
  'enjoysLowHygiene': _Field(
    editor: [
      _At(_realismTab, 'd.realismEnjoysLowHygiene'),
      _webNeedsSet,
      _relay,
    ],
    reader: [
      _At(_wear, 'ext?.@'),
      _At('lib/services/chat/prompt_injection/needs_injection.dart'),
    ],
  ),
  'ambitions': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At('lib/services/chat/prompt_injection/ambition_injection.dart')],
  ),
  'planLines': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    notRead:
        'identity that travels with the card; no chat pass reads it yet (the '
        'plan line reads the job and work days)',
  ),
  // "At work": the member's own copy first, blank fields from the library
  // card their row's origin id resolves to.
  'occupation': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At(_work, 'ext?.@')],
  ),
  'hours': _Field(
    editor: [
      _At(_detailsTab, 'd.@'),
      _At(_webRealism, '@: formatWorkHoursRange'),
      _relay,
    ],
    reader: [_At(_work, 'ext?.@')],
  ),
  'occupationBrief': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At(_work, 'ext?.@')],
  ),
  'workDays': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At(_work, 'ext?.@')],
  ),
  'birthday': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [
      _At('lib/services/chat/birthday_sync.dart', 'frontPorchExtensions?.@'),
    ],
  ),
  'likes': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At(_prefs, 'ext.@'), _At(_judges, 'ext.@')],
  ),
  'dislikes': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At(_prefs, 'ext.@'), _At(_judges, 'ext.@')],
  ),
  'intimateInto': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At(_prefs, 'ext.@'), _At(_judges, 'ext.@')],
  ),
  'intimateNotInto': _Field(
    editor: [_At(_detailsTab, 'd.@'), _webSet, _relay],
    reader: [_At(_prefs, 'ext.@'), _At(_judges, 'ext.@')],
  ),
  'sex': _Field(
    reader: [_At(_afterglow, 'ext?.@')],
    noEditor:
        'the AI creators and Enhance write it; the Edit Character page keeps '
        'it and has no control for it, in 1:1 either',
  ),
  'recovery': _Field(
    editor: [_At(_realismTab, 'd.@'), _webSet, _relay],
    reader: [_At(_afterglow, 'speaker.frontPorchExtensions?.@')],
  ),
  'inventory': _Field(
    editor: [_At(_detailsTab, 'd.worn'), _webSet, _relay],
    reader: [_At(_pockets)],
  ),
  // Verification and the Director run on the speaker, lent to the active
  // character for a group turn's judges.
  'realismVerificationEnabled': _Field(
    editor: [_At(_realismTab, 'd.@'), _webSet, _relay],
    reader: [_At(_judges)],
  ),
  'realismVerificationMaxReprocesses': _Field(
    editor: [_At(_realismTab, 'd.@'), _webSet, _relay],
    reader: [_At(_judges)],
  ),
  'realismVerificationStrictness': _Field(
    editor: [_At(_realismTab, 'd.@'), _webSet, _relay],
    reader: [_At(_judges)],
  ),
  'realismNeedsDirectorAuthority': _Field(
    editor: [_At(_realismTab, 'd.@'), _webSet, _relay],
    reader: [_At(_judges)],
  ),
  'needsPace': _Field(
    editor: [_At(_realismTab, 'd.@'), _webNeedsSet, _relay],
    reader: [_At(_wear, 'ext?.@')],
  ),
  'needsOff': _Field(
    editor: [_At(_realismTab, 'd.@'), _webNeedsSet, _relay],
    reader: [_At('lib/services/chat/chat_service_group_read.dart')],
  ),
  // The bars a member's body comes back to: each group member's own card,
  // read every turn by the group's wear.
  'needsBaselineHunger': _Field(
    editor: [_At(_realismTab, 'd.@'), _At(_webNeeds, '@'), _relay],
    reader: [_At(_baselines, 'ext.@'), _At(_wear, 'baselinesFromExtensions')],
  ),
  'needsBaselineBladder': _Field(
    editor: [_At(_realismTab, 'd.@'), _At(_webNeeds, '@'), _relay],
    reader: [_At(_baselines, 'ext.@'), _At(_wear, 'baselinesFromExtensions')],
  ),
  'needsBaselineEnergy': _Field(
    editor: [_At(_realismTab, 'd.@'), _At(_webNeeds, '@'), _relay],
    reader: [_At(_baselines, 'ext.@'), _At(_wear, 'baselinesFromExtensions')],
  ),
  'needsBaselineSocial': _Field(
    editor: [_At(_realismTab, 'd.@'), _At(_webNeeds, '@'), _relay],
    reader: [_At(_baselines, 'ext.@'), _At(_wear, 'baselinesFromExtensions')],
  ),
  'needsBaselineFun': _Field(
    editor: [_At(_realismTab, 'd.@'), _At(_webNeeds, '@'), _relay],
    reader: [_At(_baselines, 'ext.@'), _At(_wear, 'baselinesFromExtensions')],
  ),
  'needsBaselineHygiene': _Field(
    editor: [_At(_realismTab, 'd.@'), _At(_webNeeds, '@'), _relay],
    reader: [_At(_baselines, 'ext.@'), _At(_wear, 'baselinesFromExtensions')],
  ),
  'needsBaselineComfort': _Field(
    editor: [_At(_realismTab, 'd.@'), _At(_webNeeds, '@'), _relay],
    reader: [_At(_baselines, 'ext.@'), _At(_wear, 'baselinesFromExtensions')],
  ),
  // Chat appearance: UI Settings on desktop, saved to a member's row
  // (saveGroupMemberExtensions). The phone has no per-character colours,
  // lock or font, in 1:1 either.
  'avatarLocked': _Field(
    editor: [_At('lib/ui/dialogs/ui_settings_dialog.dart', 'e.copyWith(@')],
    reader: [_At('lib/ui/pages/chat_page.sidebar_widgets.dart')],
  ),
  'userBubbleColor': _Field(
    editor: [_At(_colorSlot, 'e.copyWith(@')],
    reader: [_At(_uiSettings, 'frontPorchExtensions?.@'), _bubbleCard],
  ),
  'userTextColor': _Field(
    editor: [_At(_colorSlot, 'e.copyWith(@')],
    reader: [_At(_uiSettings, 'frontPorchExtensions?.@'), _bubbleCard],
  ),
  'aiBubbleColor': _Field(
    editor: [_At(_colorSlot, 'e.copyWith(@')],
    reader: [_At(_uiSettings, 'frontPorchExtensions?.@'), _bubbleCard],
  ),
  'aiTextColor': _Field(
    editor: [_At(_colorSlot, 'e.copyWith(@')],
    reader: [_At(_uiSettings, 'frontPorchExtensions?.@'), _bubbleCard],
  ),
  'dialogueColor': _Field(
    editor: [_At(_colorSlot, 'e.copyWith(@')],
    reader: [_At(_uiSettings, 'frontPorchExtensions?.@'), _bubbleCard],
  ),
  'actionColor': _Field(
    editor: [_At(_colorSlot, 'e.copyWith(@')],
    reader: [_At(_uiSettings, 'frontPorchExtensions?.@'), _bubbleCard],
  ),
  'chatFontFamily': _Field(
    reader: [_At(_uiSettings, 'frontPorchExtensions?.@'), _bubbleCard],
    noEditor: 'no editor writes a character\'s chat font, in 1:1 either',
  ),
  'currentTask': _Field(
    reader: [_At('lib/services/chat/chat_service_speaker_objectives.dart')],
    noEditor:
        'the Current Task box was retired from every editor; a group still '
        "imports a member's authored task as their objective",
  ),
  // When a member greets (the group has no opener of its own).
  'greetingSeeds': _Field(
    editor: [
      _At(_dialogueTab, 'd.setAltGreetingSeed'),
      _At(_webPage, '@: paired.seeds'),
      _relay,
    ],
    reader: [
      _At('lib/services/chat/chat_service_greeting_seed.dart', 'ext?.@'),
      _At(
        'lib/services/chat/chat_service_greeting_seed.dart',
        '_greetingOwnerCard',
      ),
    ],
  ),
  'stableId': _Field(
    notRead:
        "the library card's identity across PNG rewrites and re-imports; a "
        'chat keys a member by its row id',
  ),
  // Lite (soft) members: set by the group's promote and demote, read for
  // every group turn.
  'tier': _Field(
    editor: [_At('lib/services/chat/group_lite.dart', 'ext.@')],
    reader: [_At(_blocks, 'speaker.isLite')],
  ),
  // The face ring is the library character's: a group member's comes from
  // the card its row's origin id resolves to.
  'favoriteAvatarId': _Field(
    editor: [
      _At('lib/ui/dialogs/avatar_gallery/avatar_gallery_controller.dart'),
    ],
    reader: [
      _At('lib/ui/pages/chat_page.sidebar_widgets.dart'),
      _At(
        'lib/ui/pages/chat_page.sidebar_widgets.dart',
        'originLibraryCardFor',
      ),
    ],
  ),
};

const _cardFields = <String, _Field>{
  'name': _Field(
    editor: [_At(_detailsTab, 'd.nameController'), _webPost, _relayCard, _row],
    reader: [_At(_blocks, 'speaker.@')],
  ),
  'description': _Field(
    editor: [
      _At(_detailsTab, 'd.descriptionController'),
      _webPost,
      _relayCard,
      _row,
    ],
    reader: [
      _At('lib/services/chat/growth_service.dart', 'card.@'),
      _At(_blocks, 'resolvedCardPersonality(speaker'),
    ],
  ),
  'personality': _Field(
    editor: [
      _At(_detailsTab, 'd.personalityController'),
      _webPost,
      _relayCard,
      _row,
    ],
    reader: [
      _At('lib/services/chat/growth_service.dart', 'card.@'),
      _At(_blocks, 'resolvedCardPersonality(speaker'),
    ],
  ),
  // A group scene shares one scenario: the group's own, else its first
  // member's.
  'scenario': _Field(
    editor: [
      _At(_detailsTab, 'd.scenarioController'),
      _webPost,
      _relayCard,
      _row,
    ],
    reader: [_At(_blocks, '_groupCharacters.first.@')],
  ),
  // When a member greets (the group has no opener of its own).
  'firstMessage': _Field(
    editor: [
      _At(_dialogueTab, 'd.firstMessageController'),
      _webPost,
      _relayCard,
      _row,
    ],
    reader: [_At(_greeting, 'member.allGreetings')],
  ),
  'mesExample': _Field(
    editor: [
      _At(_dialogueTab, 'd.mesExampleController'),
      _webPost,
      _relayCard,
      _row,
    ],
    reader: [_At(_blocks, 'speaker.@')],
  ),
  'systemPrompt': _Field(
    editor: [
      _At(_detailsTab, 'd.systemPromptController'),
      _webPost,
      _relayCard,
      _row,
    ],
    reader: [_At(_blocks, 'speaker.@')],
  ),
  'postHistoryInstructions': _Field(
    editor: [
      _At(_detailsTab, 'd.postHistoryController'),
      _webPost,
      _relayCard,
      _row,
    ],
    reader: [_At(_blocks, 'speaker.@')],
  ),
  'alternateGreetings': _Field(
    editor: [
      _At(_dialogueTab, 'd.altGreetingControllers'),
      _At(_webPage, '@: paired.greetings'),
      _relayCard,
      _row,
    ],
    reader: [_At(_greeting, 'member.allGreetings')],
  ),
  'tags': _Field(
    editor: [_At(_detailsTab, 'd.@'), _At(_webPage, '@: tags'), _relayCard],
    notRead: "library labels; no chat reads a card's tags",
  ),
  // Read when the group inherits its members' lorebooks; a group turn reads
  // the speaker's.
  'lorebook': _Field(
    editor: [
      _At(_editPage, '_loreEntries'),
      _At(_webPage, '@: lore'),
      _relayCard,
      _row,
    ],
    reader: [_At(_lore, 'ch.@')],
  ),
  // The group's Setting is its own; a member's worlds add their lorebooks
  // when the group inherits them. A member's row stores Setting and lore
  // worlds as one list.
  'worldNames': _Field(
    editor: [
      _At(_editPage, '_draft.worldChoice'),
      _At(_webPage, 'worlds: worldChoice'),
      _At(
        'lib/services/web/facade/group_member_edit.dart',
        'applyCharacterWorlds',
      ),
      _At(_rowPath, 'card.allWorldNames'),
    ],
    reader: [_At(_lore, 'ch.allWorldNames')],
  ),
  'loreWorldNames': _Field(
    editor: [
      _At(_editPage, '_draft.worldChoice'),
      _At(_webPage, 'worlds: worldChoice'),
      _At(
        'lib/services/web/facade/group_member_edit.dart',
        'applyCharacterWorlds',
      ),
      _At(_rowPath, 'card.allWorldNames'),
    ],
    reader: [_At(_lore, 'ch.allWorldNames')],
  ),
  'ttsVoice': _Field(
    editor: [_At(_detailsTab, 'd.@'), _At(_webPage, '@'), _relayCard, _row],
    reader: [_At('lib/services/chat/group_speaker_resolution.dart')],
  ),
  'creator': _Field(notRead: _credits),
  'creatorNotes': _Field(notRead: _credits),
  'characterVersion': _Field(notRead: _credits),
};

const _credits =
    'V2 credits round-trip for The Stoop and Chub; no chat reads them, and a '
    'member row keeps no copy';

/// What makes the editors above a member's: each way in opens the editor on
/// the member and saves to the member's row, and the row carries the whole
/// extensions both ways.
const _spine = <(String, String, String)>[
  (
    'lib/ui/pages/edit_group/edit_group_details_tab.dart',
    'EditCharacterPage(',
    'Edit group opens Edit Character on a member',
  ),
  (
    'lib/ui/pages/edit_group/edit_group_details_tab.dart',
    'saveGroupMemberCard(',
    "and saves it to the member's row",
  ),
  (
    'lib/ui/pages/chat_page.sidebar_widgets.dart',
    'saveGroupMemberCard(',
    "the open group chat's sidebar saves a member's edit to its row",
  ),
  (
    'lib/ui/dialogs/ui_settings_dialog.dart',
    'saveGroupMemberExtensions(',
    "UI Settings saves a member's colours and lock to its row",
  ),
  (
    'lib/services/group_member_card_save.dart',
    'ext.toJson',
    'the row stores the whole extensions, every field the codec writes',
  ),
  (
    'lib/models/group_member.dart',
    'FrontPorchExtensions.fromJson',
    'and the group loads them back',
  ),
  (
    'web_ui/src/pages/CharacterEditPage.tsx',
    'members/\${params.memberId}',
    "the phone's editor posts a member to the group's route",
  ),
  (
    'lib/services/web/routes/group_routes.dart',
    '_memberUpdate',
    'the relay takes the member edit',
  ),
  (
    'lib/services/web/facade/group_member_edit.dart',
    'applyCharacterFields(',
    "applies the page's fields to the member",
  ),
  (
    'lib/services/web/facade/group_member_edit.dart',
    'saveGroupMemberCard(',
    "and saves them to the member's row",
  ),
  (
    'lib/services/web/facade/group_member_edit.dart',
    '_saveStart(',
    "a member's start goes to the group's seed for them",
  ),
  (
    'lib/services/web/facade/character/character_card_edits.dart',
    'frontPorchFromFields(',
    "the page's Realism fields go through the relay",
  ),
];

// ── Enumerating the fields from the code ─────────────────────────────────

/// A `'key': value` entry of a map literal, with the `if (…)` condition
/// that guards it, or ''.
typedef _MapEntry = ({String key, String value, String guard});

/// Every `'key': value` entry of the map literals in [function]'s body.
List<_MapEntry> _mapEntries(DartSource source, String function) {
  final fn = source.functions
      .where((f) => f.name == function && f.body != null)
      .firstOrNull;
  if (fn == null) {
    throw StateError('${source.path} has no block-bodied $function');
  }
  final body = fn.body!;
  final code = source.code;
  final entries = <_MapEntry>[];
  for (final s in source.strings) {
    if (s.start <= body.start || s.end >= body.end) continue;
    var i = s.end;
    while (i < body.end && code[i].trim().isEmpty) {
      i++;
    }
    if (code[i] != ':') continue;
    var depth = 0, j = i + 1;
    for (; j < body.end; j++) {
      final c = code[j];
      if ('([{'.contains(c)) {
        depth++;
      } else if (')]}'.contains(c)) {
        if (depth-- == 0) break;
      } else if (c == ',' && depth == 0) {
        break;
      }
    }
    entries.add((
      key: s.body,
      value: code.substring(i + 1, j).trim(),
      guard: _guardBefore(code, s.start),
    ));
  }
  return entries;
}

/// The condition of an `if (…)` right before [offset], or ''.
String _guardBefore(String code, int offset) {
  var i = offset - 1;
  while (i >= 0 && code[i].trim().isEmpty) {
    i--;
  }
  if (i < 0 || code[i] != ')') return '';
  final close = i;
  var depth = 0;
  for (; i >= 0; i--) {
    if (code[i] == ')') depth++;
    if (code[i] == '(' && --depth == 0) break;
  }
  if (i < 0 || !code.substring(0, i).trimRight().endsWith('if')) return '';
  return code.substring(i + 1, close);
}

/// The public instance fields [className] declares (`Type name;`, or
/// `Type name = value;`): its members that are not a method, getter,
/// setter, constructor or static.
List<String> _declaredFields(DartSource source, String className) {
  final code = source.code;
  final head = RegExp('class\\s+$className\\b[^{]*\\{').firstMatch(code);
  if (head == null) throw StateError('${source.path} has no $className');
  final fields = <String>[];
  var depth = 1, paren = 0, start = head.end;
  for (var i = head.end; i < code.length && depth > 0; i++) {
    final c = code[i];
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      if (--depth == 1) start = i + 1;
    } else if (depth == 1) {
      if (c == '(') paren++;
      if (c == ')') paren--;
      if (c == ';' && paren == 0) {
        final statement = code.substring(start, i).trim();
        start = i + 1;
        if (statement.contains(
          RegExp(r'=>|\b(?:static|get|set|factory|operator)\b'),
        )) {
          continue;
        }
        final eq = statement.indexOf('=');
        final declaration = (eq < 0 ? statement : statement.substring(0, eq))
            .trim();
        // A constructor's initializer list (`) : a = b`) is not a field.
        if (declaration.contains(RegExp('[()]'))) continue;
        final name = RegExp(r'(\w+)$').firstMatch(declaration)?[1];
        if (name != null && !name.startsWith('_')) fields.add(name);
      }
    }
  }
  return fields;
}

final _extAccessor = RegExp(r'(?<![\w$.])e\.(\w+)');
final _firstName = RegExp(r'(?<![\w$.])([A-Za-z_]\w*)');

/// Extension field → the card JSON key the codec writes it under.
Map<String, String> _codecKeys() {
  final keys = <String, String>{};
  for (final e in _mapEntries(
    DartSource.read(_extCodec),
    'encodeFrontPorchExtensions',
  )) {
    if (e.value.startsWith('{')) continue; // a nested map: its keys follow
    final accessor =
        _extAccessor.firstMatch(e.value)?[1] ??
        _extAccessor.firstMatch(e.guard)?[1];
    if (accessor != null) keys[accessor] = e.key;
  }
  return keys;
}

/// Card field → the key CharacterCard.toJson writes it under.
Map<String, String> _cardKeys() {
  final keys = <String, String>{};
  for (final e in _mapEntries(DartSource.read(_cardModel), 'toJson')) {
    if (e.value.startsWith('{')) continue;
    final accessor = _firstName.firstMatch(e.value)?[1];
    if (accessor != null) keys[accessor] = e.key;
  }
  return keys;
}

// ── Checking a place ─────────────────────────────────────────────────────

final _code = <String, String>{};

String _codeOf(String path) => _code.putIfAbsent(
  path,
  () => path.endsWith('.dart')
      ? DartSource.read(path).code
      : File(path).readAsStringSync(),
);

/// [marker] as a whole token run: `ext.likes` is not found in `ext.likesX`
/// or `next.likes`.
RegExp _markerPattern(String marker) {
  final head = RegExp(r'^[\w$]').hasMatch(marker) ? r'(?<![\w$])' : '';
  final tail = RegExp(r'[\w$]$').hasMatch(marker) ? r'(?![\w$])' : '';
  return RegExp('$head${RegExp.escape(marker)}$tail');
}

/// Why [at] does not name [field] any more, or null when it does.
String? _missing(String field, _At at) {
  if (!File(at.path).existsSync()) return '${at.path} does not exist';
  final marker = at.marker.replaceAll('@', field);
  if (_markerPattern(marker).hasMatch(_codeOf(at.path))) return null;
  return '${at.path} no longer has "$marker"';
}

List<String> _shapeProblems(String owner, Map<String, _Field> fields) => [
  for (final MapEntry(key: name, value: f) in fields.entries) ...[
    if ([
          f.reader.isNotEmpty,
          f.groupWide != null,
          f.notRead != null,
          f.soloOnly != null,
        ].where((b) => b).length !=
        1)
      '$owner.$name: give it readers, or exactly one of groupWide, notRead '
          'and soloOnly',
    if (f.reader.isNotEmpty && f.editor.isEmpty && f.noEditor == null)
      '$owner.$name: a group reads it, so name its editors or say why it has '
          'none (noEditor)',
    if (f.noEditor != null && (f.editor.isNotEmpty || f.reader.isEmpty))
      '$owner.$name: noEditor is for a field a group reads and nothing edits',
    for (final reason in [f.noEditor, f.groupWide, f.notRead, f.soloOnly])
      if (reason != null && reason.trim().isEmpty)
        '$owner.$name: an exemption needs its reason',
  ],
];

List<String> _placeProblems(String owner, Map<String, _Field> fields) => [
  for (final MapEntry(key: name, value: f) in fields.entries) ...[
    for (final at in f.editor)
      if (_missing(name, at) case final why?) '$owner.$name editor: $why',
    for (final at in f.reader)
      if (_missing(name, at) case final why?) '$owner.$name reader: $why',
  ],
];

const _addAdvice =
    'A group member is the group\'s own copy of a character. Give the field '
    'a group editor (the member editor, desktop and phone) and a group '
    'reader (where a group turn reads it per member) and list them here; '
    'or, when the group\'s own switch owns it, nothing reads it at chat '
    'time, or only a 1:1-only feature does, say so with groupWide:, '
    'notRead: or soloOnly: and the reason.';

void main() {
  final declared = _declaredFields(
    DartSource.read(_extModel),
    'FrontPorchExtensions',
  );
  final codec = _codecKeys();
  final extFields = {...declared, ...codec.keys};
  final cardKeys = _cardKeys();
  final cardFields = {
    for (final MapEntry(:key) in cardKeys.entries)
      if (!_cardContainers.contains(key)) key,
  };

  test('the card fields are read from the model, the codec and toJson', () {
    expect(declared, isNotEmpty, reason: 'no fields found in $_extModel');
    expect(codec, isNotEmpty, reason: 'no keys found in $_extCodec');
    expect(cardFields, isNotEmpty, reason: 'no keys found in $_cardModel');
    expect(
      _cardContainers.difference(cardKeys.keys.toSet()),
      isEmpty,
      reason: 'CharacterCard.toJson no longer writes these; drop them',
    );
  });

  test('every extension field travels in the JSON a member row stores', () {
    final unwritten = [
      for (final f in declared)
        if (!codec.containsKey(f)) f,
    ];
    expect(
      unwritten,
      isEmpty,
      reason:
          'A group member row stores the extensions as '
          'encodeFrontPorchExtensions writes them, so a field the codec '
          'leaves out never reaches a member. Write these in $_extCodec '
          '(and read them back in decodeFrontPorchExtensions).',
    );
  });

  test('every card field says how a group member gets it', () {
    final unlisted = [
      for (final f in extFields)
        if (!_extFields.containsKey(f))
          'FrontPorchExtensions.$f '
              '(${codec[f] == null ? 'not in the card JSON' : 'key "${codec[f]}"'})',
      for (final f in cardFields)
        if (!_cardFields.containsKey(f))
          'CharacterCard.$f (key "${cardKeys[f]}")',
    ];
    expect(
      unlisted,
      isEmpty,
      reason:
          'These card fields have no entry in _extFields / _cardFields. '
          '$_addAdvice\n${unlisted.join('\n')}',
    );
  });

  test('every entry names a card field that still exists', () {
    final stale = [
      for (final f in _extFields.keys)
        if (!extFields.contains(f)) 'FrontPorchExtensions.$f',
      for (final f in _cardFields.keys)
        if (!cardFields.contains(f)) 'CharacterCard.$f',
    ];
    expect(
      stale,
      isEmpty,
      reason:
          'No such field in $_extModel, $_extCodec or $_cardModel any more; '
          'drop the entry (or rename it with the field).\n${stale.join('\n')}',
    );
  });

  test('every entry gives a reader or one reasoned exemption', () {
    final problems = [
      ..._shapeProblems('FrontPorchExtensions', _extFields),
      ..._shapeProblems('CharacterCard', _cardFields),
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('every named editor and reader still names its field', () {
    final problems = [
      ..._placeProblems('FrontPorchExtensions', _extFields),
      ..._placeProblems('CharacterCard', _cardFields),
    ];
    expect(
      problems,
      isEmpty,
      reason:
          'An editor or reader moved, or stopped handling the field. Point '
          'the entry at where a group member\'s value is edited or read now; '
          'if nothing does, the field went 1:1-only: fix that, not the '
          'entry.\n${problems.join('\n')}',
    );
  });

  test("the member editors save to the member's row", () {
    final problems = [
      for (final (path, marker, why) in _spine)
        if (_missing('', _At(path, marker)) case final missing?)
          '$why: $missing',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
