import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image_submit_error.dart';

void main() {
  test('node 28 keeps its own detail, not another node’s summary', () {
    const body = '''
{"error":{"type":"prompt_outputs_failed_validation","message":"Prompt outputs failed validation","details":""},
"node_errors":{"28":{"class_type":"UNETLoader","dependent_outputs":[],"errors":[{"type":"value_not_in_list","message":"Value not in list","details":"unet_name: 'z_image_turbo_bf16.safetensors' not in []"}]}}}
''';
    final err = parseComfySubmitFailure('http://127.0.0.1:8188', body);
    expect(err, isNotNull);
    expect(err!.nodeId, '28');
    expect(err.nodeClass, 'UNETLoader');
    expect(
      err.message,
      contains("unet_name: 'z_image_turbo_bf16.safetensors'"),
    );
    expect(err.banner, contains('http://127.0.0.1:8188'));
    expect(err.banner, contains('node 28 (UNETLoader)'));
  });

  test('a string error and a plain body are still shown', () {
    final asString = parseComfySubmitFailure(
      'http://127.0.0.1:8188',
      '{"error":"no prompt","node_errors":[]}',
    );
    expect(asString!.message, 'no prompt');
    final html = parseComfySubmitFailure(
      'http://127.0.0.1:8188',
      'bad gateway',
    );
    expect(html!.message, 'bad gateway');
  });

  test('history execution_error falls back to exception_type', () {
    final err = parseComfyHistoryError('http://127.0.0.1:8188', [
      [
        'execution_error',
        {
          'node_id': '28',
          'node_type': 'UNETLoader',
          'exception_message': '',
          'exception_type': 'RuntimeError',
        },
      ],
    ]);
    expect(err!.nodeId, '28');
    expect(err.nodeClass, 'UNETLoader');
    expect(err.message, 'RuntimeError');
  });

  test(
    'detail longer than 240 characters is capped on a character boundary',
    () {
      final emoji = '😀';
      expect(emoji.length, 2);
      expect(capDetail('${'a' * 239}$emoji'), 'a' * 239);
    },
  );

  test('an unrecognized JSON error still shows the body', () {
    final err = parseComfySubmitFailure(
      'http://127.0.0.1:8188',
      '{"detail":"Not Found"}',
    );
    expect(err!.message, contains('Not Found'));
  });

  test('a successful prompt id is not a rejection', () {
    expect(
      parseComfySubmitFailure(
        'http://127.0.0.1:8188',
        '{"prompt_id":"abc","node_errors":{}}',
      ),
      isNull,
    );
  });
}
