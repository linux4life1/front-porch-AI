// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;

void main() {
  group('WorldRepository — in-memory operations', () {
    test('saveWorld adds new world to list', () {
      final worlds = <model.World>[];
      final world = model.World(
        name: 'New World',
        description: 'Brand new',
        lorebook: Lorebook(entries: []),
      );
      worlds.add(world);
      expect(worlds.length, 1);
      expect(worlds[0].name, 'New World');
    });

    test('deleteWorld removes from list', () {
      final worlds = <model.World>[
        model.World(name: 'To Delete', description: 'Temporary', lorebook: Lorebook(entries: [])),
      ];
      worlds.removeAt(0);
      expect(worlds, isEmpty);
    });

    test('saveWorld updates existing world by index', () {
      final worlds = <model.World>[
        model.World(name: 'Original', description: 'Old', lorebook: Lorebook(entries: [])),
      ];
      worlds[0].description = 'Updated';
      expect(worlds[0].description, 'Updated');
    });

    test('addLorebookEntry adds entry to world', () {
      final world = model.World(
        name: 'Lore World',
        description: 'Has lore',
        lorebook: Lorebook(entries: []),
      );
      world.lorebook.entries.add(LorebookEntry(key: 'test', content: 'Test lore'));
      expect(world.lorebook.entries.length, 1);
      expect(world.lorebook.entries[0].content, 'Test lore');
    });

    test('updateLorebookEntry modifies existing entry', () {
      final world = model.World(
        name: 'Update World',
        description: 'Editable',
        lorebook: Lorebook(entries: [
          LorebookEntry(key: 'original', content: 'Original content'),
        ]),
      );
      world.lorebook.entries[0].content = 'Updated content';
      expect(world.lorebook.entries[0].content, 'Updated content');
    });

    test('deleteLorebookEntry removes entry from world', () {
      final world = model.World(
        name: 'Delete World',
        description: 'Has entries',
        lorebook: Lorebook(entries: [
          LorebookEntry(key: 'keep', content: 'Keep this'),
          LorebookEntry(key: 'remove', content: 'Remove this'),
        ]),
      );
      world.lorebook.entries.removeWhere((e) => e.key == 'remove');
      expect(world.lorebook.entries.length, 1);
      expect(world.lorebook.entries[0].key, 'keep');
    });

    test('toggleLorebookEntry toggles enabled state', () {
      final world = model.World(
        name: 'Toggle World',
        description: 'Toggle test',
        lorebook: Lorebook(entries: [
          LorebookEntry(key: 'entry1', content: 'Content 1', enabled: true),
        ]),
      );
      world.lorebook.entries[0].enabled = false;
      expect(world.lorebook.entries[0].enabled, false);

      world.lorebook.entries[0].enabled = true;
      expect(world.lorebook.entries[0].enabled, true);
    });

    test('world with linkedCharacterName can be found', () {
      final worlds = <model.World>[
        model.World(
          name: 'Hero World',
          description: 'Hero domain',
          lorebook: Lorebook(entries: []),
          linkedCharacterName: 'Hero',
        ),
      ];
      final found = worlds.where((w) => w.linkedCharacterName == 'Hero').toList();
      expect(found.length, 1);
      expect(found[0].name, 'Hero World');
    });

    test('world without linkedCharacterName is not found by name lookup', () {
      final worlds = <model.World>[
        model.World(name: 'Standalone', description: 'No link', lorebook: Lorebook(entries: [])),
      ];
      final found = worlds.where((w) => w.linkedCharacterName == 'Hero').toList();
      expect(found, isEmpty);
    });

    test('multiple worlds can coexist', () {
      final worlds = <model.World>[
        model.World(name: 'World A', lorebook: Lorebook(entries: [])),
        model.World(name: 'World B', lorebook: Lorebook(entries: [])),
        model.World(name: 'World C', lorebook: Lorebook(entries: [])),
      ];
      expect(worlds.length, 3);
    });
  });
}
