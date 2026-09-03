// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Additive `verification` parse: gold / blue count, anything else is none.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/backporch/backporch.dart';

void main() {
  group('stoopVerificationOf', () {
    test('gold and blue pass through', () {
      expect(stoopVerificationOf('gold'), 'gold');
      expect(stoopVerificationOf('blue'), 'blue');
    });

    test('missing, empty, and unknown are none', () {
      expect(stoopVerificationOf(null), isNull);
      expect(stoopVerificationOf(''), isNull);
      expect(stoopVerificationOf('OWNER'), isNull);
      expect(stoopVerificationOf('trusted'), isNull);
      expect(stoopVerificationOf(1), isNull);
    });
  });

  group('fromJson verification', () {
    test('BackporchUser gold / blue / missing', () {
      expect(
        BackporchUser.fromJson({
          'id': '1',
          'displayName': 'SosukeAizen',
          'verification': 'gold',
        }).verification,
        'gold',
      );
      expect(
        BackporchUser.fromJson({
          'id': '1',
          'displayName': 'Trusted',
          'verification': 'blue',
        }).verification,
        'blue',
      );
      expect(
        BackporchUser.fromJson({'id': '1', 'displayName': 'Ada'}).verification,
        isNull,
      );
    });

    test('StoopCreatorRef gold / blue / missing', () {
      expect(
        StoopCreatorRef.fromJson({
          'id': '1',
          'displayName': 'SosukeAizen',
          'verification': 'gold',
        }).verification,
        'gold',
      );
      expect(
        StoopCreatorRef.fromJson({
          'id': '1',
          'displayName': 'Trusted',
          'verification': 'blue',
        }).verification,
        'blue',
      );
      expect(
        StoopCreatorRef.fromJson({
          'id': '1',
          'displayName': 'Ada',
        }).verification,
        isNull,
      );
    });

    test('StoopCreator and StoopFollowedCreator gold / missing', () {
      expect(
        StoopCreator.fromJson({
          'id': '1',
          'displayName': 'SosukeAizen',
          'verification': 'gold',
        }).verification,
        'gold',
      );
      expect(
        StoopCreator.fromJson({'id': '1', 'displayName': 'Ada'}).verification,
        isNull,
      );
      expect(
        StoopFollowedCreator.fromJson({
          'id': '1',
          'displayName': 'Trusted',
          'verification': 'blue',
        }).verification,
        'blue',
      );
      expect(
        StoopFollowedCreator.fromJson({
          'id': '1',
          'displayName': 'Ada',
        }).verification,
        isNull,
      );
    });

    test('card creator ref rides the nested object', () {
      final card = StoopCard.fromJson({
        'id': 'c1',
        'name': 'Misty',
        'creator': {
          'id': '1',
          'displayName': 'SosukeAizen',
          'verification': 'gold',
        },
      });
      expect(card.creator?.verification, 'gold');

      final old = StoopCard.fromJson({
        'id': 'c1',
        'name': 'Misty',
        'creator': {'id': '1', 'displayName': 'Ada'},
      });
      expect(old.creator?.verification, isNull);
    });
  });
}
