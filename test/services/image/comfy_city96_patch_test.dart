// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The loader text change itself, on a stock copy held in the test. From
// image-studio-rewrite's local_model_roots_test, without its case that read a
// real ComfyUI install on the machine running the tests.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/image/comfy_gguf_city96.dart';

import 'city96_test_loader.dart';

void main() {
  test('stock City96 loader source gains the Qwen-Image path', () {
    final patched = patchCity96Loader(kStockCity96Loader);
    expect(patched.recognized, isTrue);
    expect(patched.changed, isTrue);
    expect(patched.source, contains('arch_str = "qwen_image"'));
    expect(patched.source, contains('def _qwen3vl_vision('));
    expect(patched.source, contains('arch == "qwen3vl"'));
    expect(patched.source, contains('model.visual.deepstack_merger_list'));
    final again = patchCity96Loader(patched.source);
    expect(again.changed, isFalse);
    expect(again.source, patched.source);
  });

  test('a CRLF City96 loader stays CRLF', () {
    final patched = patchCity96Loader(
      kStockCity96Loader.replaceAll('\n', '\r\n'),
    );
    expect(patched.source, contains('\r\n'));
    expect(patched.source, isNot(contains('\r\r\n')));
    expect(patched.source, contains('arch == "qwen3vl"'));
  });

  test('a loader it does not recognize is not touched', () {
    const fork = 'def gguf_sd_loader(path):\n    pass\n';
    final patch = patchCity96Loader(fork);
    expect(patch.recognized, isFalse);
    expect(patch.changed, isFalse);
    expect(patch.source, fork);
  });
}
