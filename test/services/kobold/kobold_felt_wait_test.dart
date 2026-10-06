// The wait keeping a chat costs the user, on a clock the test moves: a save
// done before the next turn starts costs nothing, a turn that starts during
// one waits for what is left of it, and the load before a reply always counts.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';

void main() {
  late Duration now;
  late KoboldFeltWait felt;

  setUp(() {
    now = Duration.zero;
    felt = KoboldFeltWait(now: () => now);
  });

  void after(int ms) => now += Duration(milliseconds: ms);

  /// A save of [chat] that takes [ms]; the next turn starts [turnAt] ms
  /// into it, or after it when null.
  void save(String chat, int ms, {int? turnAt, bool first = false}) {
    felt.saveStarts(chat);
    if (first) felt.firstIntoSlot();
    if (turnAt != null) {
      after(turnAt);
      felt.turnStarts();
      after(ms - turnAt);
    } else {
      after(ms);
    }
    felt.saveEnds(made: true);
    if (turnAt == null) felt.turnStarts();
  }

  test('a save done before the next turn starts cost nothing', () {
    expect(felt.of('A'), isNull, reason: 'nothing known yet');
    save('A', 900);
    expect(felt.of('A'), Duration.zero);
  });

  test('a turn that starts during a save waits for what is left of it; only '
      'the first start counts, and a start with no save running waits for '
      'nothing', () {
    felt.turnStarts();
    felt.saveStarts('A');
    after(200);
    felt.turnStarts();
    after(300);
    felt.turnStarts();
    after(500);
    felt.saveEnds(made: true);
    expect(felt.of('A'), const Duration(milliseconds: 800));
  });

  test('the first save into a slot, and a save not made, say nothing; only '
      'the first end of a save counts', () {
    save('A', 900, turnAt: 0, first: true);
    expect(felt.of('A'), isNull);

    felt.saveStarts('A');
    felt.turnStarts();
    after(900);
    felt.saveEnds(made: false);
    felt.saveEnds(made: true);
    expect(felt.of('A'), isNull);
  });

  test('the last three saves average, and the last load back adds to them', () {
    save('A', 300, turnAt: 0); // dropped: older than the last three
    save('A', 600); // done before the turn: nothing
    save('A', 600, turnAt: 0);
    save('A', 900, turnAt: 0);
    expect(felt.of('A'), const Duration(milliseconds: 500));

    felt.noteLoad('A', const Duration(milliseconds: 100));
    felt.noteLoad('A', const Duration(milliseconds: 50));
    expect(felt.of('A'), const Duration(milliseconds: 550));
  });

  test('each chat is its own; a deleted chat, and a new load of the model, '
      'are forgotten, with the save running then', () {
    save('A', 400, turnAt: 0);
    save('B', 200, turnAt: 0);
    felt.noteLoad('A', const Duration(milliseconds: 100));
    expect(felt.of('A'), const Duration(milliseconds: 500));
    expect(felt.of('B'), const Duration(milliseconds: 200));

    felt.forget('A');
    expect(felt.of('A'), isNull);
    expect(felt.of('B'), const Duration(milliseconds: 200));

    felt.saveStarts('B');
    felt.turnStarts();
    felt.clear();
    after(900);
    felt.saveEnds(made: true);
    expect(felt.of('B'), isNull);
  });
}
