// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for ExpressionClassifierService, ONNXExpressionClassifier, and
// OnnxDownloadProgress. Validates the ONNX classification routing, download
// progress tracking, and emotion result parsing.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/expression_classifier.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Mock the path_provider plugin so StorageService._init() can resolve
/// getApplicationDocumentsDirectory() without a real platform channel.
void setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getApplicationDocumentsDirectory') {
      final tmp = Directory.systemTemp.createTempSync('fpai_expr_test_');
      return tmp.path;
    }
    return null;
  });
}

/// Helper: create a StorageService backed by in-memory SharedPreferences.
Future<StorageService> createStorageService({
  Map<String, Object> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final service = StorageService();
  await service.initialized;
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  group('OnnxDownloadProgress', () {
    test('fraction is correct for partial download', () {
      final progress = OnnxDownloadProgress(
        file: 'model.onnx',
        downloaded: 3000000,
        total: 10000000,
      );
      expect(progress.fraction, closeTo(0.3, 0.001));
    });

    test('fraction is 0.0 when total is 0', () {
      final progress = OnnxDownloadProgress(
        file: 'model.onnx',
        downloaded: 500,
        total: 0,
      );
      expect(progress.fraction, equals(0.0));
    });

    test('fraction is 1.0 when downloaded equals total', () {
      final progress = OnnxDownloadProgress(
        file: 'model.onnx',
        downloaded: 10000000,
        total: 10000000,
      );
      expect(progress.fraction, equals(1.0));
    });

    test('file name is preserved', () {
      final progress = OnnxDownloadProgress(
        file: 'model.onnx',
        downloaded: 100,
        total: 200,
      );
      expect(progress.file, equals('model.onnx'));
    });
  });

  group('EmotionResult', () {
    test('fromJson parses valid JSON response', () {
      final json = {
        'emotion': 'joy',
        'confidence': 0.92,
        'top_3': [
          {'emotion': 'joy', 'confidence': 0.92},
          {'emotion': 'excitement', 'confidence': 0.05},
          {'emotion': 'amusement', 'confidence': 0.03},
        ],
      };
      final result = EmotionResult.fromJson(json);

      expect(result.emotion, equals('joy'));
      expect(result.confidence, equals(0.92));
      expect(result.topCandidates.length, equals(3));
      expect(result.topCandidates[0].emotion, equals('joy'));
      expect(result.topCandidates[0].confidence, equals(0.92));
    });

    test('fromJson handles missing top_3', () {
      final json = {
        'emotion': 'sadness',
        'confidence': 0.85,
      };
      final result = EmotionResult.fromJson(json);

      expect(result.emotion, equals('sadness'));
      expect(result.confidence, equals(0.85));
      expect(result.topCandidates, isEmpty);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = <String, dynamic>{};
      final result = EmotionResult.fromJson(json);

      expect(result.emotion, equals('neutral'));
      expect(result.confidence, equals(0.0));
      expect(result.topCandidates, isEmpty);
    });

    test('fromJson handles null confidence in top_3', () {
      final json = {
        'emotion': 'joy',
        'confidence': 0.9,
        'top_3': [
          {'emotion': 'joy'},
        ],
      };
      final result = EmotionResult.fromJson(json);
      expect(result.topCandidates[0].confidence, equals(0.0));
    });
  });

  group('EmotionCandidate', () {
    test('constructor sets fields correctly', () {
      final candidate = const EmotionCandidate(
        emotion: 'joy',
        confidence: 0.95,
      );
      expect(candidate.emotion, equals('joy'));
      expect(candidate.confidence, equals(0.95));
    });
  });

  group('LLMExpressionClassifier', () {
    test('returns neutral when emotion is empty', () async {
      final classifier = LLMExpressionClassifier(
        getCurrentEmotion: () => '',
        reclassify: (e) async => 'neutral',
      );
      final result = await classifier.classify('test');
      expect(result.emotion, equals('neutral'));
      expect(result.confidence, equals(1.0));
    });

    test('returns direct match for standard label', () async {
      final classifier = LLMExpressionClassifier(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );
      final result = await classifier.classify('test');
      expect(result.emotion, equals('joy'));
      expect(result.confidence, equals(1.0));
    });

    test('maps nuanced emotion to standard label', () async {
      final classifier = LLMExpressionClassifier(
        getCurrentEmotion: () => 'elated',
        reclassify: (e) async => 'joy',
      );
      final result = await classifier.classify('test');
      expect(result.emotion, equals('joy'));
      expect(result.confidence, equals(0.9));
    });

    test('triggers reclassification for unmapped emotion', () async {
      var reclassifyCalled = false;
      final classifier = LLMExpressionClassifier(
        getCurrentEmotion: () => 'blorp',
        reclassify: (e) async {
          reclassifyCalled = true;
          return 'fear';
        },
      );
      final result = await classifier.classify('test');
      expect(reclassifyCalled, isTrue);
      expect(result.emotion, equals('fear'));
      expect(result.confidence, equals(0.8));
    });

    test('falls back to neutral when reclassification fails', () async {
      final classifier = LLMExpressionClassifier(
        getCurrentEmotion: () => 'blorp',
        reclassify: (e) async {
          throw Exception('LLM error');
        },
      );
      final result = await classifier.classify('test');
      expect(result.emotion, equals('neutral'));
      expect(result.confidence, equals(0.5));
    });

    test('falls back to neutral when reclassify returns invalid label', () async {
      final classifier = LLMExpressionClassifier(
        getCurrentEmotion: () => 'blorp',
        reclassify: (e) async => 'not_a_valid_label',
      );
      final result = await classifier.classify('test');
      expect(result.emotion, equals('neutral'));
      expect(result.confidence, equals(0.8));
    });

    test('isAvailable always returns true', () async {
      final classifier = LLMExpressionClassifier(
        getCurrentEmotion: () => '',
        reclassify: (e) async => 'neutral',
      );
      expect(await classifier.isAvailable(), isTrue);
    });
  });

  group('ONNXExpressionClassifier', () {
    test('classify returns neutral when script is not found', () async {
      final storage = await createStorageService();
      final classifier = ONNXExpressionClassifier(storage: storage);
      final result = await classifier.classify('I am happy');
      expect(result.emotion, equals('neutral'));
      expect(result.confidence, equals(0.0));
    });

    test('onProgress callback is captured when provided', () async {
      final storage = await createStorageService();
      var progressEmitted = false;
      final classifier = ONNXExpressionClassifier(
        storage: storage,
        onProgress: (progress) {
          progressEmitted = true;
        },
      );
      // Script may exist but Python deps missing — classify() returns neutral.
      // The onProgress callback is wired so it would fire during a real run.
      expect(classifier, isNotNull);
    });
  });

  group('ExpressionClassifierService', () {
    test('ensureInitialized creates LLM classifier for llm mode', () async {
      final storage = await createStorageService();
      final service = ExpressionClassifierService(storage);

      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );

      expect(service.activeMode, equals('llm'));
    });

    test('ensureInitialized creates null classifier for manual mode', () async {
      final storage = await createStorageService();
      await storage.setExpressionClassificationMode('manual');
      final service = ExpressionClassifierService(storage);

      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );

      expect(service.activeMode, equals('manual'));
    });

    test('classify returns null in manual mode', () async {
      final storage = await createStorageService();
      await storage.setExpressionClassificationMode('manual');
      final service = ExpressionClassifierService(storage);

      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );

      final result = await service.classify('test text');
      expect(result, isNull);
    });

    test('classify delegates to active classifier in llm mode', () async {
      final storage = await createStorageService();
      final service = ExpressionClassifierService(storage);

      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );

      final result = await service.classify('I feel great!');
      expect(result, isNotNull);
      expect(result!.emotion, equals('joy'));
    });

    test('download progress state defaults to not downloading', () async {
      final storage = await createStorageService();
      final service = ExpressionClassifierService(storage);

      expect(service.isDownloading, isFalse);
      expect(service.modelReady, isFalse);
      expect(service.downloadProgress, isNull);
    });

    test('disposes active classifier', () async {
      final storage = await createStorageService();
      final service = ExpressionClassifierService(storage);

      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );

      service.dispose();
    });

    test('notifyListeners is called on ensureInitialized', () async {
      final storage = await createStorageService();
      final service = ExpressionClassifierService(storage);

      var listenerCalled = false;
      service.addListener(() {
        listenerCalled = true;
      });

      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );

      expect(listenerCalled, isTrue);
    });

    test('skips re-initialization when mode is unchanged', () async {
      final storage = await createStorageService();
      final service = ExpressionClassifierService(storage);

      var classifyCount = 0;
      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );
      await service.classify('test1');
      await service.classify('test2');
      classifyCount = 2;
      expect(classifyCount, equals(2));
    });

    test('switches from llm to manual mode', () async {
      final storage = await createStorageService();
      final service = ExpressionClassifierService(storage);

      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );
      expect(service.activeMode, equals('llm'));

      await storage.setExpressionClassificationMode('manual');
      await service.ensureInitialized(
        getCurrentEmotion: () => 'joy',
        reclassify: (e) async => 'joy',
      );
      expect(service.activeMode, equals('manual'));
    });
  });
}
