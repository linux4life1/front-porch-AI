// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The physical core count read from `lscpu -p=core`. Under `-p=core` lscpu
// prints ONE column, the core number of each logical processor, so a core
// that runs two threads is listed twice. The first text below is the real
// output of util-linux 2.38.1 on an 18-core machine; the other two are the
// same format for hyper-threaded machines, whose threads sit either apart
// (Intel numbers them 0..5, then 0..5 again) or side by side (AMD).
//
// The Linux branch used to read a second column that this output does not
// have, so it never found a core and fell back to the logical count.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';

const _header =
    '''# The following is the parsable format, which can be fed to other
# programs. Each different item in every column has an unique ID
# starting usually from zero.
# Core
''';

String _lscpu(Iterable<int> cores) => '$_header${cores.join('\n')}\n';

void main() {
  test('every core of a machine with one thread each is counted', () {
    expect(physicalCoresFromLscpu(_lscpu(List.generate(18, (i) => i))), 18);
  });

  test('a core that runs two threads is counted once, whichever way its '
      'threads are numbered', () {
    final apart = [
      ...List.generate(6, (i) => i),
      ...List.generate(6, (i) => i),
    ];
    final together = [
      for (var i = 0; i < 6; i++) ...[i, i],
    ];
    expect(physicalCoresFromLscpu(_lscpu(apart)), 6);
    expect(physicalCoresFromLscpu(_lscpu(together)), 6);
  });

  test('text with no core in it says so, so the caller falls back', () {
    expect(physicalCoresFromLscpu(''), isNull);
    expect(physicalCoresFromLscpu(_header), isNull);
    expect(physicalCoresFromLscpu('\n\n'), isNull);
  });
}
