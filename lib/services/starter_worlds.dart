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
//
// Starter worlds: a handful of original example worlds with places inside
// them, bundled as ordinary .fpworld envelopes under assets/worlds/starter
// (written by tools/gen_starter_worlds.mjs). Nothing is seeded: the Worlds
// page (desktop and web) lists the index and adds one on request through
// WorldRepository.importWorldJson, the same path a picked .fpworld file
// takes, so a starter becomes an ordinary editable, deletable world.

import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/world_repository.dart';

/// One row of the bundled index: what the picker shows without opening
/// the world's own file.
class StarterWorldInfo {
  const StarterWorldInfo({
    required this.id,
    required this.name,
    required this.blurb,
    required this.climate,
    required this.customClimate,
    required this.places,
    required this.ownClimates,
    required this.loreEntries,
  });

  /// File stem under [StarterWorlds.kAssetDir]; also the web route's id.
  final String id;
  final String name;
  final String blurb;

  /// The root's climate display name (e.g. `Tundra`, `Rainforest`).
  final String climate;

  /// True when the root carries a hand-authored climate, not a built-in.
  final bool customClimate;

  /// Places inside the root.
  final int places;

  /// How many of those places own a climate instead of inheriting.
  final int ownClimates;

  /// Lore entries across the root and its places.
  final int loreEntries;

  factory StarterWorldInfo.fromJson(Map<String, dynamic> json) {
    int count(String key) => (json[key] as num?)?.toInt() ?? 0;
    return StarterWorldInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      blurb: json['blurb']?.toString() ?? '',
      climate: json['climate']?.toString() ?? '',
      customClimate: json['customClimate'] == true,
      places: count('places'),
      ownClimates: count('ownClimates'),
      loreEntries: count('loreEntries'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'blurb': blurb,
    'climate': climate,
    'customClimate': customClimate,
    'places': places,
    'ownClimates': ownClimates,
    'loreEntries': loreEntries,
  };
}

/// Lists and adds the bundled starter worlds. Plain Dart over an
/// [AssetBundle] and the [WorldRepository]; the desktop dialog and the web
/// facade each hold one.
class StarterWorlds {
  StarterWorlds(this._repo, {AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final WorldRepository _repo;
  final AssetBundle _bundle;

  /// Where the bundles live (listed in pubspec.yaml `assets:`).
  static const kAssetDir = 'assets/worlds/starter';

  /// The envelope id every bundle's root carries, which the importer keeps
  /// as the new root's [model.World.sourceId].
  static String sourceIdFor(String id) => 'starter-$id';

  Future<List<StarterWorldInfo>>? _index;

  /// Adds in flight by starter id: a second request for the same starter
  /// while the first is still writing joins it instead of importing twice
  /// (a double click on desktop, a double POST from the phone).
  final Map<String, Future<model.World>> _adding = {};

  /// The picker's list, in bundle order. Read once per instance; a failed
  /// read is not cached, so the next open tries again.
  Future<List<StarterWorldInfo>> index() {
    return _index ??= _readIndex().catchError((Object e) {
      _index = null;
      throw e;
    });
  }

  Future<List<StarterWorldInfo>> _readIndex() async {
    // Uncached in the bundle: this instance keeps the parsed list itself.
    final raw = jsonDecode(
      await _bundle.loadString('$kAssetDir/index.json', cache: false),
    );
    final rows = raw is Map ? raw['worlds'] : null;
    if (rows is! List) {
      throw const FormatException('starter index has no worlds list');
    }
    return [
      for (final row in rows)
        if (row is Map)
          StarterWorldInfo.fromJson(Map<String, dynamic>.from(row)),
    ];
  }

  /// Whether [id] names a bundled starter. Ids come off the web route, so
  /// only an index id ever reaches the asset path.
  Future<bool> has(String id) async => (await index()).any((w) => w.id == id);

  /// The raw .fpworld envelope for [id]. Throws [ArgumentError] for an id
  /// that is not in the index.
  Future<Map<String, dynamic>> package(String id) async {
    if (!await has(id)) {
      throw ArgumentError.value(id, 'id', 'not a starter world');
    }
    final raw = jsonDecode(
      await _bundle.loadString('$kAssetDir/$id.fpworld', cache: false),
    );
    if (raw is! Map) {
      throw FormatException('starter world $id is not a JSON object');
    }
    return Map<String, dynamic>.from(raw);
  }

  /// Whether a root added from [id] is in the library now. Adding again is
  /// allowed: the importer keeps both and numbers the names, as it does for
  /// any .fpworld file imported twice.
  bool isAdded(String id) => _repo.placeWorlds.any(
    (w) => w.parentWorldId == null && w.sourceId == sourceIdFor(id),
  );

  /// Import starter [id] as a new root with its places; returns the root.
  Future<model.World> add(String id) {
    final pending = _adding[id];
    if (pending != null) return pending;
    // Block body on purpose: `remove` returns this very future, and a
    // whenComplete callback that returns a future is awaited, so an arrow
    // here would make the add wait on itself forever.
    final run = _import(id).whenComplete(() {
      _adding.remove(id);
    });
    _adding[id] = run;
    return run;
  }

  Future<model.World> _import(String id) async =>
      _repo.importWorldJson(await package(id));
}
