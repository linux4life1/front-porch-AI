// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A vision model that quotes inside a field (`"flaw": "a \"melted\" ear"`)
// left the QC note as a lone backslash: the reader stopped at the first
// escaped quote. The reply goes through the real run() and parse.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/expression_pack_service.dart';

void main() {
  test('a quoted flaw reaches the note whole', () async {
    final slot = ExpressionSlot('sad')
      ..state = ExpressionSlotState.done
      ..bytes = Uint8List.fromList([1, 2]);
    final qc = ExpressionPackQc(
      slots: [slot],
      baseImageB64: 'QkFTRQ==',
      fire: ({required prompt, required imagesB64}) async =>
          r'{"same_person": true, "expression": "sad", '
          r'"flaw": "a \"melted\" ear"}',
    );

    await qc.run();

    expect(qc.unparsedCount, 0);
    expect(slot.qc!.pass, isTrue);
    expect(slot.qc!.note, 'a "melted" ear');
  });
}
