// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Portable world package (.fpworld) — a place with lore (+ optional biome).
// See docs/design/living-worlds.md. Envelope is Stoop-ready; biome may be null
// until the world carries a climate.

import 'dart:convert';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';

/// Current .fpworld formatVersion written by this app.
const int kFpWorldFormatVersion = 1;

/// Encode a [World] (and optional biome snapshot) as a .fpworld JSON map.
Map<String, dynamic> encodeFpWorld({
  required World world,
  Map<String, dynamic>? biome,
  String? author,
  String? appVersion,
}) {
  final loreJson = world.lorebook.toJson();
  return {
    'formatVersion': kFpWorldFormatVersion,
    'id': world.id,
    'name': world.name,
    'description': world.description,
    if (world.coverImage != null && world.coverImage!.isNotEmpty)
      'cover': world.coverImage,
    // Single book today; array reserves multi-lorebook without a format break.
    'lorebook': loreJson,
    'lorebooks': [loreJson],
    if (world.climateEnabled) 'biome': biome,
    'climate_enabled': world.climateEnabled,
    // Additive: older apps ignore unknown envelope keys (mixed-fleet rule).
    if (world.climateEnabled && world.placeTraits.isNotEmpty)
      'place_traits': world.placeTraits,
    'meta': {
      if (author != null && author.isNotEmpty) 'author': author,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      if (appVersion != null && appVersion.isNotEmpty) 'appVersion': appVersion,
      if (world.sourceId != null) 'sourceId': world.sourceId,
    },
  };
}

String encodeFpWorldString({
  required World world,
  Map<String, dynamic>? biome,
  String? author,
  String? appVersion,
}) => const JsonEncoder.withIndent('  ').convert(
  encodeFpWorld(
    world: world,
    biome: biome,
    author: author,
    appVersion: appVersion,
  ),
);

/// Result of parsing a .fpworld (or degenerate lorebook) file.
class FpWorldPackage {
  final World world;
  final Map<String, dynamic>? biome;
  final int formatVersion;

  const FpWorldPackage({
    required this.world,
    this.biome,
    this.formatVersion = kFpWorldFormatVersion,
  });
}

/// Parse .fpworld JSON, or a bare ST/Chub/FPAI lorebook as a degenerate world.
FpWorldPackage decodeFpWorld(Map<String, dynamic> json) {
  final isEnvelope =
      json.containsKey('formatVersion') ||
      (json.containsKey('id') &&
          json.containsKey('name') &&
          (json.containsKey('lorebook') || json.containsKey('lorebooks')));

  if (!isEnvelope) {
    // Bare world-info / lorebook → degenerate place (no biome).
    final world = World.fromJson(json);
    return FpWorldPackage(world: world, biome: null, formatVersion: 0);
  }

  final formatVersion = (json['formatVersion'] as num?)?.toInt() ?? 1;
  final id = json['id']?.toString();
  final name = json['name']?.toString() ?? 'Imported World';
  final description = json['description']?.toString() ?? '';
  final cover = json['cover']?.toString();

  Lorebook lorebook;
  if (json['lorebooks'] is List && (json['lorebooks'] as List).isNotEmpty) {
    // v1: merge all books' entries into one (multi-book storage is later).
    final books = <Lorebook>[];
    for (final item in json['lorebooks'] as List) {
      if (item is Map<String, dynamic>) {
        books.add(Lorebook.fromJson(item));
      } else if (item is Map) {
        books.add(Lorebook.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    if (books.isEmpty) {
      lorebook = Lorebook(entries: []);
    } else if (books.length == 1) {
      lorebook = books.first;
    } else {
      lorebook = Lorebook(
        entries: [for (final b in books) ...b.entries],
        scanDepth: books.first.scanDepth,
        tokenBudget: books.first.tokenBudget,
        recursiveScanning: books.first.recursiveScanning,
      );
    }
  } else if (json['lorebook'] is Map) {
    lorebook = Lorebook.fromJson(
      Map<String, dynamic>.from(json['lorebook'] as Map),
    );
  } else {
    lorebook = Lorebook(entries: []);
  }

  final climateEnabled = readWorldClimateEnabled(json) ?? true;
  Map<String, dynamic>? biome;
  final rawBiome = json['biome'];
  if (climateEnabled && rawBiome is Map) {
    biome = Map<String, dynamic>.from(rawBiome);
  }

  final meta = json['meta'] is Map
      ? Map<String, dynamic>.from(json['meta'] as Map)
      : <String, dynamic>{};

  return FpWorldPackage(
    formatVersion: formatVersion,
    biome: biome,
    world: World(
      id: id,
      name: name,
      description: description,
      lorebook: lorebook,
      coverImage: cover,
      sourceId: meta['sourceId']?.toString() ?? id,
      formatVersion: formatVersion,
      climateEnabled: climateEnabled,
      placeTraits: climateEnabled && json['place_traits'] is Map
          ? Map<String, dynamic>.from(json['place_traits'] as Map)
          : null,
    ),
  );
}

FpWorldPackage decodeFpWorldString(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw FormatException('World file must be a JSON object');
  }
  return decodeFpWorld(Map<String, dynamic>.from(decoded));
}
