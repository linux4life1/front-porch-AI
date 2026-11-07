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

import 'settings_base.dart';

/// The chat sidebar's section order, remembered on this computer: one global
/// arrangement per surface, not per chat. A mixin beside [UiSettings] because
/// that file is near the size limit (the same shape as [LibraryViewPrefs]).
///
/// The desktop scrolling body and its accordion leaves share one vocabulary;
/// the web insight column and its Chat Tools sections have their own, so each
/// surface keeps its own list. The order resolution rule is the contract:
/// stored ids are never dropped, visible ids follow the stored order, and an
/// id the stored list does not know (a new or conditional section) appends per
/// the default order. A section hidden right now keeps its stored slot for
/// when it reappears.

/// Top-level ids in the shipped default order (the old hard-coded body order).
const _kSidebarOrderDefault = [
  'director',
  'one_shot_eval',
  'tool_calling_pill',
  'lite_banner',
  'author_note',
  'wiki',
  'character_state',
  'journal_memory',
  'objectives',
  'story_tools',
];

/// Leaf ids per accordion, in the shipped default order.
const _kLeafContainers = ['story_tools', 'journal_memory', 'character_state'];
const _kLeafDefaults = {
  'story_tools': ['chaos', 'afk', 'places', 'lorebook', 'chat_lorebook'],
  'journal_memory': ['summary', 'journal', 'memory', 'growth'],
  // Character State's own portions, split so each is dragged on its own.
  // member_card leads so group mode resolves [member_card, time]; 1:1 hides
  // it and resolves the bars/fixation/needs/ambitions/pockets/time it shows.
  // Fixation rides just after the bars it belongs to, but moves on its own.
  'character_state': [
    'realism_off',
    'member_card',
    'bond_bars',
    'fixation',
    'needs',
    'ambitions',
    'pockets',
    'time',
  ],
};

/// Web insight children, in the shipped default order. This list is the
/// web's own vocabulary (it must match `SIDEBAR_DEFAULTS.insight` in
/// `web_ui/src/components/sidebarReorder.tsx` — the PWA resolves against
/// ids it actually renders); the Character State split is desktop-side.
const _kWebInsightDefault = [
  'one_shot_eval',
  'tool_calling_pill',
  'cast_chips',
  'portrait',
  'author_note',
  'realism_stats',
  'chat_tools',
  'places',
  'lorebook',
];

/// Web Chat Tools sections, in the shipped default order.
const _kWebToolsDefault = [
  'realism_toggle',
  'needs_toggle',
  'context_budget',
  'wiki',
  'memory',
  'ambitions',
  'pockets',
  'our_story',
  'promises',
  'belongings',
  'chaos',
  'objectives',
  'recap',
  'scene_time',
  'nsfw',
  'group_settings',
];

mixin SidebarLayout on SettingsBase {
  List<String> _sidebarOrder = List.of(_kSidebarOrderDefault);
  final Map<String, List<String>> _sidebarLeafOrder = {};
  List<String> _webSidebarOrder = List.of(_kWebInsightDefault);
  List<String> _webSidebarToolsOrder = List.of(_kWebToolsDefault);
  bool _sidebarLayoutLocked = false;

  void loadSidebarLayout() {
    _sidebarLayoutLocked = prefs?.getBool(k('sidebar_layout_locked')) ?? false;
    _sidebarOrder = _readList(k('sidebar_order'), _kSidebarOrderDefault);
    for (final container in _kLeafContainers) {
      _sidebarLeafOrder[container] = _readList(
        k('sidebar_leaf_order_$container'),
        _kLeafDefaults[container]!,
      );
    }
    _webSidebarOrder = _readList(k('web_sidebar_order'), _kWebInsightDefault);
    _webSidebarToolsOrder = _readList(
      k('web_sidebar_tools_order'),
      _kWebToolsDefault,
    );
  }

  /// A stored JSON list, else the fallback. A corrupt value falls back rather
  /// than throwing, so a bad write cannot wedge the sidebar.
  List<String> _readList(String key, List<String> fallback) {
    final raw = prefs?.getString(key);
    if (raw == null) return List.of(fallback);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.cast<String>().toList();
    } catch (_) {
      // fall through to the fallback
    }
    return List.of(fallback);
  }

  /// [visible] ids in stored order; ids the stored list does not know append
  /// per [defaults]. Stored ids that are not visible are skipped here but stay
  /// in the stored list.
  List<String> _resolve(
    List<String> stored,
    List<String> visible,
    List<String> defaults,
  ) {
    final out = <String>[];
    for (final id in stored) {
      if (visible.contains(id)) out.add(id);
    }
    for (final id in defaults) {
      if (visible.contains(id) && !out.contains(id)) out.add(id);
    }
    for (final id in visible) {
      if (!out.contains(id)) out.add(id);
    }
    return out;
  }

  /// Merge a new visible order into the stored list: visible ids take their new
  /// sequence, hidden ids keep their slots. A visible id the stored list never
  /// knew appends at the end.
  List<String> _merge(List<String> stored, List<String> visibleOrder) {
    final visible = visibleOrder.toSet();
    final out = <String>[];
    var next = 0;
    for (final id in stored) {
      if (visible.contains(id)) {
        if (next < visibleOrder.length) out.add(visibleOrder[next++]);
      } else {
        out.add(id);
      }
    }
    while (next < visibleOrder.length) {
      out.add(visibleOrder[next++]);
    }
    return out;
  }

  /// The top-level ids to paint, in order.
  List<String> sidebarOrderFor(List<String> visible) =>
      _resolve(_sidebarOrder, visible, _kSidebarOrderDefault);

  /// The leaf ids of [container] to paint, in order.
  List<String> sidebarLeafOrderFor(String container, List<String> visible) =>
      _resolve(
        _sidebarLeafOrder[container] ?? _kLeafDefaults[container]!,
        visible,
        _kLeafDefaults[container]!,
      );

  /// The web insight children to paint, in order.
  List<String> webSidebarOrderFor(List<String> visible) =>
      _resolve(_webSidebarOrder, visible, _kWebInsightDefault);

  /// The web Chat Tools sections to paint, in order.
  List<String> webSidebarToolsOrderFor(List<String> visible) =>
      _resolve(_webSidebarToolsOrder, visible, _kWebToolsDefault);

  /// The raw stored lists (visible ids in order, hidden ids kept). The web
  /// reads these and resolves against its own vocabulary and defaults.
  List<String> get sidebarOrder => List.of(_sidebarOrder);
  Map<String, List<String>> get sidebarLeafOrder => {
    for (final e in _sidebarLeafOrder.entries) e.key: List.of(e.value),
  };
  List<String> get webSidebarOrder => List.of(_webSidebarOrder);
  List<String> get webSidebarToolsOrder => List.of(_webSidebarToolsOrder);

  /// True while the user has locked the sidebar layout: every grip renders
  /// inert so a section cannot be moved by accident. One switch for both
  /// surfaces, like the order itself.
  bool get sidebarLayoutLocked => _sidebarLayoutLocked;

  Future<void> setSidebarOrder(List<String> visibleOrder) async {
    _sidebarOrder = _merge(_sidebarOrder, visibleOrder);
    await prefs?.setString(k('sidebar_order'), jsonEncode(_sidebarOrder));
    notify();
  }

  Future<void> setSidebarLeafOrder(
    String container,
    List<String> visibleOrder,
  ) async {
    final stored =
        _sidebarLeafOrder[container] ?? List.of(_kLeafDefaults[container]!);
    _sidebarLeafOrder[container] = _merge(stored, visibleOrder);
    await prefs?.setString(
      k('sidebar_leaf_order_$container'),
      jsonEncode(_sidebarLeafOrder[container]),
    );
    notify();
  }

  Future<void> setWebSidebarOrder(List<String> visibleOrder) async {
    _webSidebarOrder = _merge(_webSidebarOrder, visibleOrder);
    await prefs?.setString(k('web_sidebar_order'), jsonEncode(_webSidebarOrder));
    notify();
  }

  Future<void> setWebSidebarToolsOrder(List<String> visibleOrder) async {
    _webSidebarToolsOrder = _merge(_webSidebarToolsOrder, visibleOrder);
    await prefs?.setString(
      k('web_sidebar_tools_order'),
      jsonEncode(_webSidebarToolsOrder),
    );
    notify();
  }

  /// Lock or unlock the layout. Stored as a bool and cleared when unlocked, so
  /// a fresh install (and the default) is unlocked.
  Future<void> setSidebarLayoutLocked(bool locked) async {
    _sidebarLayoutLocked = locked;
    if (locked) {
      await prefs?.setBool(k('sidebar_layout_locked'), true);
    } else {
      await prefs?.remove(k('sidebar_layout_locked'));
    }
    notify();
  }

  /// Restore every surface's shipped default order and forget the stored keys.
  /// The lock is deliberately left alone: resetting the order must not quietly
  /// re-open a layout the user asked to protect.
  Future<void> resetSidebarLayout() async {
    _sidebarOrder = List.of(_kSidebarOrderDefault);
    _sidebarLeafOrder.clear();
    _webSidebarOrder = List.of(_kWebInsightDefault);
    _webSidebarToolsOrder = List.of(_kWebToolsDefault);
    await prefs?.remove(k('sidebar_order'));
    for (final container in _kLeafContainers) {
      await prefs?.remove(k('sidebar_leaf_order_$container'));
    }
    await prefs?.remove(k('web_sidebar_order'));
    await prefs?.remove(k('web_sidebar_tools_order'));
    notify();
  }
}
