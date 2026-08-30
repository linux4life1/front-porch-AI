// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/pages/home/open_section_env.dart';

void main() {
  test('OPEN_SECTION omit/default is a no-op', () {
    expect(OpenSectionEnv.name, isEmpty);
    expect(OpenSectionEnv.enabled, isFalse);
    expect(OpenSectionEnv.isKnown(OpenSectionEnv.name), isFalse);
  });

  test('the four OPEN_SECTION tokens are recognized', () {
    expect(OpenSectionEnv.isKnown(OpenSectionEnv.journal), isTrue);
    expect(OpenSectionEnv.isKnown(OpenSectionEnv.objectives), isTrue);
    expect(OpenSectionEnv.isKnown(OpenSectionEnv.timestrip), isTrue);
    expect(OpenSectionEnv.isKnown(OpenSectionEnv.edit), isTrue);
  });

  test('empty and unknown tokens are not recognized', () {
    expect(OpenSectionEnv.isKnown(''), isFalse);
    expect(OpenSectionEnv.isKnown('nope'), isFalse);
    expect(OpenSectionEnv.isKnown('Journal'), isFalse);
  });

  test('edit apply skips group and lite; otherwise opens', () {
    var opened = 0;
    OpenSectionEnv.apply(
      section: OpenSectionEnv.edit,
      isGroup: false,
      isLite: false,
      onOpenEdit: () => opened++,
    );
    expect(opened, 1);

    OpenSectionEnv.apply(
      section: OpenSectionEnv.edit,
      isGroup: true,
      isLite: false,
      onOpenEdit: () => opened++,
    );
    OpenSectionEnv.apply(
      section: OpenSectionEnv.edit,
      isGroup: false,
      isLite: true,
      onOpenEdit: () => opened++,
    );
    expect(opened, 1);
  });

  test('empty apply is a no-op even with callbacks', () {
    var touched = 0;
    OpenSectionEnv.apply(
      section: '',
      isGroup: false,
      isLite: false,
      expandJournal: () => touched++,
      onOpenEdit: () => touched++,
    );
    expect(touched, 0);
  });
}
