// When the slot keeper looks after chats and when it stays out, decided from
// what the engine was given and what the model is.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/utils/utils.dart';

const _plain = GGUFModelInfo(
  nLayers: 32,
  nHeads: 32,
  nKvHeads: 8,
  nEmbd: 4096,
  kvBytesPerToken: 131072,
);

/// What auto mode stages for an ordinary model: no smart cache.
Map<String, dynamic> _config([Map<String, dynamic> more = const {}]) => {
  'contextsize': 16384,
  'noswa': true,
  'nofastforward': false,
  ...more,
};

KoboldKeeperPlan _plan({
  bool ownEngine = true,
  Map<String, dynamic>? config,
  GGUFModelInfo? info = _plain,
  KoboldKeeperMemory? memory,
}) => koboldKeeperPlan(
  ownEngine: ownEngine,
  config: config ?? _config(),
  info: info,
  memory: memory,
);

void main() {
  test("an ordinary model on the app's own engine is kept", () {
    expect(_plan().keeps, isTrue);
  });

  test('an engine the app did not start is left alone', () {
    final plan = _plan(ownEngine: false);
    expect(plan.keeps, isFalse);
    expect(plan.why, isNotNull);
  });

  test('a config not known yet is asked about again', () {
    final plan = koboldKeeperPlan(ownEngine: true, config: null, info: _plain);
    expect(plan.undecided, isTrue);
    expect(plan.keeps, isFalse);
  });

  test("smart cache on is the user's own choice, and the keeper stays out", () {
    expect(_plan(config: _config({'smartcache': 3})).keeps, isFalse);
    expect(_plan(config: _config({'smartcache': 0})).keeps, isTrue);
    expect(_plan(config: _config({'smartcache': '2'})).keeps, isFalse);
  });

  test('fast forward off means a saved chat could not be picked up', () {
    expect(_plan(config: _config({'nofastforward': true})).keeps, isFalse);
  });

  test('a model that could not be read is not kept', () {
    expect(_plan(info: null).keeps, isFalse);
  });

  test("a model with recurrent layers stays with KoboldCpp's own cache", () {
    const hybrid = GGUFModelInfo(
      nLayers: 32,
      nHeads: 32,
      nKvHeads: 8,
      nEmbd: 4096,
      kvBytesPerToken: 65536,
      recurrentStateBytes: 40000000,
    );
    final plan = _plan(info: hybrid);
    expect(plan.keeps, isFalse);
    expect(plan.why, contains('smart cache'));
  });

  test('sliding window left to KoboldCpp for a model that has it', () {
    const windowed = GGUFModelInfo(
      nLayers: 32,
      nHeads: 32,
      nKvHeads: 8,
      nEmbd: 4096,
      kvBytesPerToken: 131072,
      slidingWindow: 1024,
    );
    final left = {'contextsize': 16384, 'nofastforward': false};
    expect(_plan(info: windowed, config: left).keeps, isFalse);
    expect(
      _plan(info: windowed, config: {...left, 'noswa': true}).keeps,
      isTrue,
      reason: 'a config that switches it off decides it',
    );
    expect(
      _plan(info: _plain, config: left).keeps,
      isTrue,
      reason: 'a model without it is not affected',
    );
  });

  test('an engine set to answer several requests at once is not kept', () {
    expect(_plan(config: _config({'parallelrequests': 4})).keeps, isFalse);
    expect(_plan(config: _config({'parallelrequests': 1})).keeps, isTrue);
  });

  group('how many chats', () {
    test('unknown memory keeps one', () {
      expect(_plan().chats, 1);
    });

    test("plenty of memory keeps one for each of KoboldCpp's five slots", () {
      final plan = _plan(
        memory: (slotMb: 1000, freeRamMb: 64000, modelRamMb: 8000),
      );
      expect(plan.chats, kKoboldSaveSlots);
    });

    test('less memory keeps fewer, counting a full context for each', () {
      // 12,100 free, 8,000 for the model, 2,048 set aside: 2,052 left for
      // slots of 1,000 each.
      final plan = _plan(
        memory: (slotMb: 1000, freeRamMb: 12100, modelRamMb: 8000),
      );
      expect(plan.chats, 2);
    });

    test('no room keeps nothing and says so', () {
      final plan = _plan(
        memory: (slotMb: 1000, freeRamMb: 9000, modelRamMb: 8000),
      );
      expect(plan.keeps, isFalse);
      expect(plan.why, contains('memory'));
    });
  });
}
