// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-character Pockets & Wardrobe flag on FrontPorchExtensions.
// Missing / null must stay ON so old cards keep working when the Porch Life
// global is on. Explicit false is the only off. The card JSON omits the key
// when on so existing goldens and Stoop cards stay byte-identical.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/web/util/realism_extensions_json.dart';

void main() {
  group('FrontPorchExtensions.pocketsEnabled', () {
    test('defaults on so a new card does not silently veto Pockets', () {
      expect(FrontPorchExtensions().pocketsEnabled, isTrue);
    });

    test('missing JSON key treats as on — old cards keep working', () {
      final ext = FrontPorchExtensions.fromJson({
        'realism_engine': {'enabled': true, 'needs_sim_enabled': true},
      });
      expect(ext.pocketsEnabled, isTrue);
      expect(
        ext.toJson()['realism_engine'],
        isNot(contains('pockets_enabled')),
        reason: 'on is the default; writing it would churn every old card',
      );
    });

    test('null JSON value treats as on', () {
      final ext = FrontPorchExtensions.fromJson({
        'realism_engine': {'pockets_enabled': null},
      });
      expect(ext.pocketsEnabled, isTrue);
    });

    test('explicit false round-trips on the card', () {
      final ext = FrontPorchExtensions(pocketsEnabled: false);
      expect(ext.pocketsEnabled, isFalse);

      final json = ext.toJson();
      expect(json['realism_engine']['pockets_enabled'], isFalse);

      final back = FrontPorchExtensions.fromJson(json);
      expect(back.pocketsEnabled, isFalse);
      expect(back.copyWith().pocketsEnabled, isFalse);
      expect(back.copyWith(pocketsEnabled: true).pocketsEnabled, isTrue);
    });

    test('explicit true omits the key so a save does not dirty old cards', () {
      final ext = FrontPorchExtensions(pocketsEnabled: true);
      expect(
        ext.toJson()['realism_engine'],
        isNot(contains('pockets_enabled')),
      );
    });

    test('web bridge round-trips explicit off and keeps omitted as on', () {
      final off = frontPorchFromFields({'pocketsEnabled': false});
      expect(off.pocketsEnabled, isFalse);
      expect(frontPorchToJson(off)['pocketsEnabled'], isFalse);

      final omitted = frontPorchFromFields(const {});
      expect(omitted.pocketsEnabled, isTrue);

      final kept = frontPorchFromFields(const {}, base: off);
      expect(
        kept.pocketsEnabled,
        isFalse,
        reason: 'a phone save that omits the key must not flip an authored off',
      );
    });
  });
}
