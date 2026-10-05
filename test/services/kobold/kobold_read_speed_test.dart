// How fast the engine reads, from the line KoboldCpp prints after every
// request: only reads big enough to time count, the biggest recent ones lead
// (reading slows as a prompt grows), and a new load of the model starts over.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';

String _line(int read, double seconds) =>
    'Processed:$read in ${seconds.toStringAsFixed(2)}s '
    '(${(read / seconds).toStringAsFixed(2)}T/s), '
    'Generated:16/16 in 0.50s (32.00T/s)\n';

void main() {
  test('nothing is known before a read big enough to time', () {
    final speed = KoboldReadSpeed();
    expect(speed.timeToRead(1000, 1), isNull);

    speed.note(_line(400, 0.1), 1); // a reply after a load: too small
    expect(speed.timeToRead(1000, 1), isNull);
  });

  test('the biggest reads decide: reading slows as a prompt grows, so short '
      'prompts read fast do not stand for a whole chat', () {
    final speed = KoboldReadSpeed()
      ..note(_line(2000, 1.25), 1) // 1,600 tokens a second
      ..note(_line(600, 0.2), 1); // 3,000: a short helper prompt
    expect(speed.timeToRead(1000, 1), const Duration(milliseconds: 625));

    for (var i = 0; i < 12; i++) {
      speed.note(_line(520, 0.1), 1);
    }
    expect(
      speed.timeToRead(1000, 1),
      const Duration(milliseconds: 625),
      reason: 'many short fast reads outvoted the big one',
    );

    speed
      ..note(_line(4000, 5.0), 1) // 800
      ..note(_line(3000, 2.5), 1); // 1,200
    // Of 4,000 at 800, 3,000 at 1,200 and 2,000 at 1,600: the middle one.
    expect(speed.timeToRead(1000, 1)!.inMilliseconds, 833);
  });

  test('a line split over two pieces of output still counts', () {
    final speed = KoboldReadSpeed()
      ..note('Processed:2000 in 2.00s (1000.0', 1)
      ..note('0T/s), Generated:16/16 in 0.50s (32.00T/s)\n', 1);
    expect(speed.timeToRead(1000, 1), const Duration(seconds: 1));
  });

  test('another load of the model starts over', () {
    final speed = KoboldReadSpeed()..note(_line(2000, 2.0), 1);
    expect(speed.timeToRead(1000, 2), isNull);

    speed.note(_line(2000, 1.0), 2);
    expect(speed.timeToRead(1000, 2), const Duration(milliseconds: 500));
    expect(speed.timeToRead(1000, 1), isNull, reason: 'the old load is gone');
  });
}
