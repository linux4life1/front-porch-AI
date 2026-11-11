// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// ONE UI PARITY. The desktop 1:1 chat sidebar is the baseline; a group chat
// shows the same controls in the same places, and the web app shows the same
// sections and Character State items in the same order. This reads the
// orders out of the code (never a list typed here except the mapping and
// exemption tables, which carry their reasons) and fails when one side moves
// without the other.
//
// Desktop: lib/services/storage/settings/sidebar_layout.dart (default orders),
// character_state/character_state_group.dart (what a chat shows) and
// sidebar_body.dart (where Group Dynamics sits). Web: ChatSidebar.tsx, whose
// WIDE_DEFAULTS is the section order and whose `case 'character_state'` JSX is
// the render order of the Character State items. The web has no leaf-order
// constant (it renders in JSX order), so each leaf is located by a marker
// string in that JSX and the markers' source order is the web order.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _layout = 'lib/services/storage/settings/sidebar_layout.dart';
const _stateDart =
    'lib/ui/chat_components/sidebar/character_state/character_state_group.dart';
const _bodyDart = 'lib/ui/chat_components/sidebar/sidebar_body.dart';
const _webSidebar = 'web_ui/src/components/ChatSidebar.tsx';

/// Section ids that exist on one side only, with why. Every other id must be
/// spelled the same on both sides, in the same order.
const _desktopOnlySections = {
  'lite_banner':
      'The desktop shows a banner section for a lite guest. The web says the '
      'same thing inside Character State ("Lite NPC — no realism or needs '
      'tracking for this guest."), which is the only place it matters there.',
};
const _webOnlySections = {
  'cast':
      'The web keeps the cast roster chips in the reorderable list; the '
      'desktop draws its roster chips above the sidebar body, outside the '
      'reorderable list, in the same place on screen (top).',
};

/// Desktop section id -> web section id, when they are spelled differently.
/// Empty today: both sides use the same ids. A rename on one side must add a
/// row here, or the test names the id that has no partner.
const _sectionIdMap = <String, String>{};

/// Character State leaf ids the desktop lists but never renders. Kept so a
/// stored order that names it still resolves.
const _deadLeafIds = {
  'member_card':
      'Left over from the pre-PR-2 group card. Nothing renders it; it is '
      'never in the visible list, so it resolves to nothing in either mode.',
};

/// Leaves a chat shows differently in a group than in 1:1. None: every
/// leaf is gated by the same rule in both modes. Add one here, with a reason,
/// only if the maintainer rules the difference in.
const _groupDiffersLeaves = <String, String>{};

/// Items only a 1:1 chat has in Character State. None: a leaf missing in a
/// group would be drift. Add one here, with a reason, only if the plan rules
/// it out.
const _oneToOneOnlyLeaves = <String, String>{};

/// Where each Character State leaf starts in the web JSX, in `case
/// 'character_state'`. A leaf with no web twin would be listed in
/// _noWebTwin with a reason.
const _webLeafMarkers = {
  'realism_off': 'realism-off',
  'bond_bars': 'label="Short-Term Bond"',
  'fixation': 'stat-fixation',
  'needs': '💗 Needs',
  'ambitions': 'state-ambitions',
  'pockets': 'state-pockets',
  'time': 'className="state-time"',
};
const _noWebTwin = <String, String>{};

String _read(String path) => File(path).readAsStringSync();

List<String> _ids(String listBody) => RegExp(
  r"""['"]([a-z_]+)['"]""",
).allMatches(listBody).map((m) => m.group(1)!).toList();

String _stripLineComments(String s) =>
    s.split('\n').map((l) => l.replaceFirst(RegExp(r'\s//.*$'), '')).join('\n');

List<String> _dartList(String source, String pattern) {
  final m = RegExp(
    pattern,
    dotAll: true,
  ).firstMatch(_stripLineComments(source));
  if (m == null) fail('Could not find $pattern in the Dart source.');
  return _ids(m.group(1)!);
}

/// The web JSX of `case 'character_state':` up to the next case.
String _webStateCase(String tsx) {
  final start = tsx.indexOf("case 'character_state':");
  final end = tsx.indexOf("case 'journal_memory':");
  if (start < 0 || end < start) {
    fail("web ChatSidebar.tsx lost its case 'character_state' block.");
  }
  return tsx.substring(start, end);
}

List<String> _byOffset(Map<String, int> at) {
  final entries = at.entries.toList()..sort((a, b) => a.value - b.value);
  return [for (final e in entries) e.key];
}

void main() {
  final layout = _read(_layout);
  final stateDart = _read(_stateDart);
  final bodyDart = _read(_bodyDart);
  final web = _read(_webSidebar);

  final desktopSections = _dartList(
    layout,
    r'_kSidebarOrderDefault\s*=\s*\[(.*?)\];',
  );
  final desktopLeaves = _dartList(layout, r"'character_state'\s*:\s*\[(.*?)\]");

  test('desktop and web default section order are the same list', () {
    final webSections = _ids(
      RegExp(
            r'const WIDE_DEFAULTS\s*=\s*\[(.*?)\];',
            dotAll: true,
          ).firstMatch(web)?.group(1) ??
          fail('web ChatSidebar.tsx lost WIDE_DEFAULTS.'),
    );

    // Every desktop id has a web partner or a reasoned exemption, and the
    // other way round. Neither side may gain a section silently.
    final unpartnered = <String>[
      for (final id in desktopSections)
        if (!_desktopOnlySections.containsKey(id) &&
            !webSections.contains(_sectionIdMap[id] ?? id))
          'desktop "$id" has no web section',
      for (final id in webSections)
        if (!_webOnlySections.containsKey(id) &&
            !desktopSections.any((d) => (_sectionIdMap[d] ?? d) == id))
          'web "$id" has no desktop section',
    ];
    expect(unpartnered, isEmpty, reason: unpartnered.join('\n'));

    final desktopShared = [
      for (final id in desktopSections)
        if (!_desktopOnlySections.containsKey(id)) _sectionIdMap[id] ?? id,
    ];
    final webShared = [
      for (final id in webSections)
        if (!_webOnlySections.containsKey(id)) id,
    ];
    expect(
      webShared,
      desktopShared,
      reason:
          'The web ChatSidebar WIDE_DEFAULTS and the desktop '
          '_kSidebarOrderDefault must list the shared sections in the same '
          'order (one UI, however it is used).',
    );
  });

  test('the exemption tables name ids that exist', () {
    expect(
      _desktopOnlySections.keys.every(desktopSections.contains),
      isTrue,
      reason: 'a _desktopOnlySections id is no longer in the desktop list',
    );
    final webSections = RegExp(
      r'const WIDE_DEFAULTS\s*=\s*\[(.*?)\];',
      dotAll: true,
    ).firstMatch(web)!.group(1)!;
    expect(
      _webOnlySections.keys.every(_ids(webSections).contains),
      isTrue,
      reason: 'a _webOnlySections id is no longer in the web list',
    );
    expect(
      _deadLeafIds.keys.every(desktopLeaves.contains),
      isTrue,
      reason: 'a _deadLeafIds id is no longer in the desktop leaf list',
    );
  });

  test('desktop and web Character State show the same leaves in order', () {
    final webCase = _webStateCase(web);
    final at = <String, int>{};
    for (final e in _webLeafMarkers.entries) {
      final i = webCase.indexOf(e.value);
      if (i < 0) {
        fail('web Character State lost the "${e.key}" leaf (${e.value}).');
      }
      at[e.key] = i;
    }
    final webOrder = _byOffset(at);

    final desktopLive = [
      for (final id in desktopLeaves)
        if (!_deadLeafIds.containsKey(id) && !_noWebTwin.containsKey(id)) id,
    ];
    expect(
      webOrder,
      desktopLive,
      reason:
          'web Character State renders $webOrder; the desktop '
          '_kLeafDefaults[character_state] is $desktopLive. Same leaves, '
          'same order, or add a reasoned exemption.',
    );

    // Afterglow and Lust ride with the bonds on the desktop (BondBars) and
    // sit between the bonds and Fixation on the web.
    final afterglow = webCase.indexOf('aria-label="Afterglow"');
    expect(afterglow, greaterThan(at['bond_bars']!));
    expect(afterglow, lessThan(at['fixation']!));
  });

  test('a group shows the same Character State leaves as 1:1', () {
    final visible = _dartList(
      stateDart,
      r'final visible = <String>\[(.*?)\n    \];',
    );
    final portions = RegExp(
      r"case '([a-z_]+)':",
    ).allMatches(_stripLineComments(stateDart)).map((m) => m.group(1)!).toSet();

    // One list, one switch, for both modes: every default leaf (bar the dead
    // id) is offered and rendered by the same code.
    final live = desktopLeaves.where((id) => !_deadLeafIds.containsKey(id));
    expect(visible.toSet(), live.toSet(), reason: 'visible vs defaults');
    expect(portions, live.toSet(), reason: 'rendered portions vs defaults');

    // Only the declared leaves may be gated on the mode.
    final body = RegExp(
      r'final visible = <String>\[(.*?)\n    \];',
      dotAll: true,
    ).firstMatch(_stripLineComments(stateDart))!.group(1)!;
    final gated = <String>{};
    // Split on the list's top-level commas (a conditional entry is
    // `if (cond) 'id'`): an entry mentioning isGroup is gated on the mode.
    for (final entry in body.split(RegExp(r",\s*\n\s*(?=if|')"))) {
      final id = _ids(entry.substring(entry.lastIndexOf('if')));
      if (entry.contains('isGroup') && id.isNotEmpty) gated.add(id.last);
    }
    expect(
      gated,
      _groupDiffersLeaves.keys.toSet(),
      reason:
          'A leaf gated on isGroup shows differently in a group than in 1:1; '
          'declare it in _groupDiffersLeaves with a reason, or remove the gate.',
    );
    expect(
      _oneToOneOnlyLeaves.keys.every(live.contains),
      isTrue,
      reason: 'a _oneToOneOnlyLeaves id is no longer a leaf',
    );
  });

  test('Group Dynamics is the only group-only section, directly under '
      'Character State', () {
    // Desktop: not a top-level id, mounted inside the character_state case,
    // after the Character State widget.
    expect(desktopSections, isNot(contains('group_dynamics')));
    final dCase = bodyDart.substring(
      bodyDart.indexOf("case 'character_state':"),
    );
    final dEnd = dCase.indexOf("case 'journal_memory':");
    final dBlock = dCase.substring(0, dEnd);
    expect(dBlock, contains('GroupDynamicsSection('));
    expect(
      dBlock.indexOf('GroupDynamicsSection('),
      greaterThan(dBlock.indexOf('CharacterStateGroup(')),
    );

    // Web: same placement, inside the character_state case, after the
    // Character State card and its last leaf.
    final wCase = _webStateCase(web);
    final dyn = wCase.indexOf('group-dynamics');
    expect(dyn, greaterThan(wCase.indexOf('className="state-time"')));
    expect(web, isNot(contains("'group_dynamics',")));
  });

  test('the Memory leaf has the same links, in the same order, and the same '
      'greyed-switch note on both sides', () {
    const dir = 'lib/ui/chat_components/sidebar/journal_memory';
    final panel = _read('$dir/memory_panel.dart');
    final labels = RegExp(
      r"label:\s*'([^'\n]+?)(?:\$\{|')",
    ).allMatches(panel.substring(panel.indexOf('_link(')));
    expect([for (final m in labels) m.group(1)!.trim()].take(3).toList(), [
      'Settings',
      'Sources',
      'Data Bank',
    ], reason: 'the desktop links moved; the PWA order must follow');
    final tsx = _read('web_ui/src/components/ChatToolsMemoryBank.tsx');
    final at = [
      tsx.indexOf('aria-pressed={showSettings}'),
      tsx.indexOf('aria-pressed={showSources}'),
      tsx.indexOf('setShowBank(true)'),
    ];
    expect(at, everyElement(greaterThan(-1)));
    expect(at[0], lessThan(at[1]));
    expect(at[1], lessThan(at[2]));

    final noteSrc = _read('$dir/memory_off_everywhere_note.dart');
    final dartNote = RegExp(r'text =([^;]+);').firstMatch(noteSrc);
    expect(dartNote, isNotNull);
    final dartText = RegExp(
      r'"([^"]*)"',
    ).allMatches(dartNote!.group(1)!).map((m) => m.group(1)).join();
    final webNote = RegExp(
      r'MEMORY_OFF_EVERYWHERE =\s*"([^"]+)"',
    ).firstMatch(_read('web_ui/src/components/ChatToolsMemory.tsx'));
    expect(webNote, isNotNull);
    expect(dartText, webNote!.group(1));
  });

  // PR 5: one editor for 1:1 and group members (docs/design/group-editor.md).
  test(
    'the member editor is the 1:1 editor plus the notice and "In the group", '
    'with Time & Day, Worlds and Chaos Mode greyed',
    () {
      final details = File(
        'lib/ui/pages/edit_character_page/edit_character_details_tab.dart',
      ).readAsStringSync();
      final order = RegExp(
        r"title: '(Identity|Voice|Personality & World|Advanced Prompts)'|"
        r'IdentityChipLists\(|EditCharacterRealismSection\(|'
        r'GroupMemberSection\(|groupMemberNotice\(|characterInGroupsNote\(',
      ).allMatches(details).map((m) => m.group(0)!).toList();
      expect(order, [
        'groupMemberNotice(',
        'characterInGroupsNote(',
        "title: 'Identity'",
        "title: 'Voice'",
        "title: 'Personality & World'",
        "title: 'Advanced Prompts'",
        'IdentityChipLists(',
        'EditCharacterRealismSection(',
        'GroupMemberSection(',
      ], reason: 'member mode adds the notice first and its section last');
      final realism = File(
        'lib/ui/pages/edit_character_page/edit_character_realism_section.dart',
      ).readAsStringSync();
      expect(realism, contains('timeDayLockedTooltip'));
      expect(realism, contains('chaosLockedTooltip'));
      expect(
        File(
          'lib/ui/pages/edit_character_page/edit_character_page.dart',
        ).readAsStringSync(),
        isNot(contains('member_group_view')),
        reason: 'there is no member-only twin of the editor',
      );
    },
  );

  test('Edit group has the 1:1 editor\'s four tabs and the spec\'s Details '
      'sections in order', () {
    final tabs = File(
      'lib/ui/pages/edit_character_page/edit_character_scaffold.dart',
    ).readAsStringSync();
    expect(
      RegExp(r"text: '(\w+)'").allMatches(tabs).map((m) => m.group(1)).toList(),
      ['Details', 'Dialogue', 'Lorebook', 'Worlds'],
    );
    final page = File('lib/ui/pages/edit_group_page.dart').readAsStringSync();
    expect(page, contains('EditCharacterScaffold('));
    final tab = File(
      'lib/ui/pages/edit_group/edit_group_details_tab.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'(Edit\w+Card)\(',
      ).allMatches(tab).map((m) => m.group(1)).toList(),
      [
        'EditGroupIdentityCard',
        'EditGroupTurnsCard',
        'EditGroupVoiceCard',
        'EditGroupPersonalityCard',
        'EditGroupAdvancedPromptsCard',
        'EditGroupTagsCard',
        'EditGroupRealismCard',
        'EditGroupStatsCard',
      ],
    );
  });
}
