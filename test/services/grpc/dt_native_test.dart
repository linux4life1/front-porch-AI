// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// Cross-language golden tests for the pure-Dart Draw Things client.
//
// Every golden hex string below was produced by the PYTHON reference stack
// this client replaced — imageService_pb2 (protobuf runtime), client.py's
// build_config_flatbuffer / image_to_nnc_tensor, and the fpzip pip package
// — so these tests pin the Dart implementation to the exact bytes the
// legacy sidecar produced/consumed. That Python stack (tools/
// dt-grpc-python) was deleted with the sidecar retirement; the goldens are
// frozen reference data now (history has the generators if ever needed).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/services/grpc/dt_native/draw_things_native_client.dart';
import 'package:front_porch_ai/services/grpc/dt_native/dt_config_fb.dart';
import 'package:front_porch_ai/services/grpc/dt_native/dt_fpzip.dart';
import 'package:front_porch_ai/services/grpc/dt_native/dt_proto.dart';
import 'package:front_porch_ai/services/grpc/dt_native/dt_tensor.dart';

Uint8List hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String toHex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

/// Minimal FlatBuffers vtable reader used to compare buffers semantically.
class _FbTable {
  final Uint8List b;
  final ByteData d;
  final int pos; // table start
  _FbTable(Uint8List buf, this.pos)
    : b = buf,
      d = ByteData.sublistView(buf);

  static _FbTable root(Uint8List buf) =>
      _FbTable(buf, ByteData.sublistView(buf).getUint32(0, Endian.little));

  /// Absolute offset of [slot]'s value, or null when absent.
  int? _field(int slot) {
    final vt = pos - d.getInt32(pos, Endian.little);
    final vtSize = d.getUint16(vt, Endian.little);
    final entry = 4 + slot * 2;
    if (entry + 2 > vtSize) return null;
    final rel = d.getUint16(vt + entry, Endian.little);
    return rel == 0 ? null : pos + rel;
  }

  int? u16(int slot) =>
      _field(slot).map((o) => d.getUint16(o, Endian.little));
  int? u32(int slot) =>
      _field(slot).map((o) => d.getUint32(o, Endian.little));
  int? i8(int slot) => _field(slot).map((o) => d.getInt8(o));
  int? i32(int slot) => _field(slot).map((o) => d.getInt32(o, Endian.little));
  double? f32(int slot) =>
      _field(slot).map((o) => d.getFloat32(o, Endian.little));
  bool? boolean(int slot) => _field(slot).map((o) => d.getUint8(o) != 0);

  String? str(int slot) {
    final o = _field(slot);
    if (o == null) return null;
    final s = o + d.getUint32(o, Endian.little);
    final len = d.getUint32(s, Endian.little);
    return String.fromCharCodes(Uint8List.sublistView(b, s + 4, s + 4 + len));
  }

  List<_FbTable>? tableVector(int slot, Uint8List buf) {
    final o = _field(slot);
    if (o == null) return null;
    final v = o + d.getUint32(o, Endian.little);
    final len = d.getUint32(v, Endian.little);
    return List.generate(len, (i) {
      final elem = v + 4 + i * 4;
      return _FbTable(buf, elem + d.getUint32(elem, Endian.little));
    });
  }
}

extension on int? {
  T? map<T>(T Function(int) f) => this == null ? null : f(this!);
}

/// Reads every GenerationConfiguration field the builder can set, so the
/// Dart and Python buffers can be compared semantically.
Map<String, Object?> _readConfig(Uint8List buf) {
  final t = _FbTable.root(buf);
  return {
    'startWidth': t.u16(1),
    'startHeight': t.u16(2),
    'seed': t.u32(3),
    'steps': t.u32(4),
    'guidance': t.f32(5),
    'strength': t.f32(6),
    'model': t.str(7),
    'sampler': t.i8(8),
    'batchCount': t.u32(9),
    'batchSize': t.u32(10),
    'seedMode': t.i8(17),
    'loras': t
        .tableVector(20, buf)
        ?.map(
          (l) => {'file': l.str(0), 'weight': l.f32(1), 'mode': l.i8(2) ?? 0},
        )
        .toList(),
    'maskBlur': t.f32(21),
    'faceRestoration': t.str(22),
    'refinerModel': t.str(28),
    'refinerStart': t.f32(38),
    'numFrames': t.u32(46),
    'sharpness': t.f32(48),
    'shift': t.f32(49),
    'preserveOriginalAfterInpaint': t.boolean(58),
    'resolutionDependentShift': t.boolean(71),
    'teaCacheStart': t.i32(72),
    'teaCacheEnd': t.i32(73),
    'teaCacheThreshold': t.f32(74),
    'teaCache': t.boolean(75),
    'teaCacheMaxSkipSteps': t.i32(78),
    'causalInferenceEnabled': t.boolean(79),
    'causalInference': t.i32(80),
    'causalInferencePad': t.i32(81),
    'cfgZeroStar': t.boolean(82),
  };
}

/// The representative config used for the Python golden (mirrors what the
/// service builds for a real generation, teaCache on, one LoRA).
Map<String, dynamic> goldenCfg() => {
  'model': 'test.ckpt',
  'start_width': 16,
  'start_height': 16,
  'seed': 12345,
  'steps': 8,
  'guidance_scale': 4.5,
  'strength': 1.0,
  'shift': 3.0,
  'sampler': 16,
  'seed_mode': 2,
  'tea_cache': true,
  'tea_cache_threshold': 0.3,
  'cfg_zero_star': false,
  'resolution_dependent_shift': false,
  'mask_blur': 1.5,
  'sharpness': 0.0,
  'loras': [
    {'file': 'l.safetensors', 'weight': 0.8, 'mode': 0},
  ],
};

const _configFbGolden =
    'a00000009c003c0000003a003800340030002c0028002400230000000000000000000000000000000000220000000000040014000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001c000000000000000000000000000000000000000000000000000000000000000000000000000000000000001b00080000000c0013009c00000038000000020000009a99993e000000010000c03f000000000000404000000210480000000000803f00009040080000003930000010001000010000000c00000008000c000800040008000000cdcc4c3f040000000d0000006c2e7361666574656e736f727300000009000000746573742e636b7074000000';

void main() {
  group('dt_proto (goldens from python protobuf runtime)', () {
    test('EchoRequest("models") bytes match', () {
      expect(toHex(encodeEchoRequest('models')), '0a066d6f64656c73');
    });

    test('EchoReply decodes message + files', () {
      final r = EchoReply.decode(
        hex(
          '0a0548454c4c4f1206612e636b70741212625f6c6f72612e7361666574656e73'
          '6f727312087661652e636b7074',
        ),
      );
      expect(r.message, 'HELLO');
      expect(r.files, ['a.ckpt', 'b_lora.safetensors', 'vae.ckpt']);
    });

    test('skipping an unknown length-delimited field lands exactly past it', () {
      // Regression: Draw Things' Echo replies carry a ~20KB model-metadata
      // JSON in a field the client skips. ProtoReader.skip used
      // `_i += readVarint()` — compound assignment reads the OLD offset
      // before readVarint() advances past the length bytes, so the reader
      // resumed 1-5 bytes short and parsed blob content as protobuf tags.
      // That was the intermittent DATA_LOSS on connect and the reason every
      // native generation dropped. The 0x2c bytes at the blob's tail decode
      // as wire type 4, so this test throws if the bug ever comes back.
      final blob = List<int>.filled(200, 0)..setRange(198, 200, [0x2c, 0x2c]);
      final reply = EchoReply.decode([
        0x0a, 0x02, ...'hi'.codeUnits, // message = "hi"
        0x1a, 0xc8, 0x01, ...blob, // unknown field 3, len 200 (2-byte varint)
        0x12, 0x06, ...'a.ckpt'.codeUnits, // files: "a.ckpt"
        0x30, 0x01, // unknown varint field 6 (trailing, like real replies)
      ]);
      expect(reply.message, 'hi');
      expect(reply.files, ['a.ckpt']);
    });

    test('ImageGenerationRequest bytes match python', () {
      final req = ImageGenerationRequest(
        prompt: 'a porch at dusk',
        negativePrompt: 'blurry',
        configuration: hex(_configFbGolden),
        scaleFactor: 1,
        user: 'front-porch-ai',
      );
      expect(
        toHex(req.encode()),
        '10012a0f6120706f726368206174206475736b3206626c757272793a9c02'
        '$_configFbGolden'
        '520e66726f6e742d706f7263682d6169',
      );
    });

    test('ImageGenerationResponse decodes signpost + images', () {
      final resp = ImageGenerationResponse.decode(hex('0a0301020312041a020805'));
      expect(resp.generatedImages.single, [1, 2, 3]);
      expect(resp.signpost, DtSignpost.sampling);
      expect(resp.samplingStep, 5);
    });
  });

  group('dt_config_fb', () {
    // The Dart and Python FlatBuffers builders emit different (equally valid)
    // physical layouts — Dart keeps trailing empty vtable slots, Python trims
    // them — so byte-equality is the wrong assertion. Instead both buffers
    // are decoded with a minimal vtable reader and compared FIELD BY FIELD,
    // which is exactly what the Draw Things server sees.
    test('GenerationConfiguration fields match python flatbuffers', () {
      final dartBuf = buildGenerationConfig(goldenCfg());
      final pyBuf = hex(_configFbGolden);
      expect(_readConfig(dartBuf), _readConfig(pyBuf));
    });

    test('python golden decodes to the intended values (reader sanity)', () {
      final f = _readConfig(hex(_configFbGolden));
      expect(f['model'], 'test.ckpt');
      expect(f['seed'], 12345);
      expect(f['steps'], 8);
      expect(f['guidance'], closeTo(4.5, 1e-6));
      expect(f['sampler'], 16);
      expect(f['seedMode'], 2);
      expect(f['shift'], closeTo(3.0, 1e-6));
      expect(f['teaCache'], true);
      expect(f['resolutionDependentShift'], false);
      expect(f['loras'], [
        {'file': 'l.safetensors', 'weight': 0.800000011920929, 'mode': 0},
      ]);
    });
  });

  group('dt_tensor', () {
    test('float16 conversion roundtrips key values', () {
      for (final v in [-1.0, -0.5, 0.0, 0.25, 0.999, 1.0]) {
        expect(halfToFloat(floatToHalf(v)), closeTo(v, 0.001));
      }
      expect(floatToHalf(-1.0), 0xbc00);
      expect(floatToHalf(1.0), 0x3c00);
      expect(floatToHalf(0.0), 0x0000);
    });

    test('imageToNncTensor matches python image_to_nnc_tensor', () {
      // 2x2 PNG produced by PIL: (0,0,0) (255,255,255) / (128,64,32) (10,200,90)
      final png = hex(
        '89504e470d0a1a0a0000000d4948445200000002000000020802000000fdd49a73'
        '0000001649444154789c63606060f8ffff3f43838302d789280021bb050a965702'
        'c00000000049454e44ae426082',
      );
      final tensor = imageToNncTensor(png, targetWidth: 2, targetHeight: 2);
      expect(
        toHex(tensor),
        '0000000001000000020000000000020000000000010000000200000002000000'
        '0300000000000000000000000000000000000000000000000000000000000000'
        '0000000000bc00bc00bc003c003c003c041cf8b7feb95fbb8d38b5b4',
      );
    });

    test('decodeGeneratedImage passes PNG through untouched', () {
      final png = hex(
        '89504e470d0a1a0a0000000d4948445200000002000000020802000000fdd49a73'
        '0000001649444154789c63606060f8ffff3f43838302d789280021bb050a965702'
        'c00000000049454e44ae426082',
      );
      expect(decodeGeneratedImage(png), png);
    });

    test('decodeGeneratedImage decodes a RAW float32 NNC tensor', () {
      // Hand-build identifier=0, f32, dims (1,2,2,3), values ramp -1..0.833.
      final vals = List<double>.generate(12, (i) => i / 6.0 - 1.0);
      final data = Uint8List(68 + 12 * 4);
      final bd = ByteData.sublistView(data);
      bd.setUint32(0, 0, Endian.little);
      bd.setInt32(4, 0x1, Endian.little);
      bd.setInt32(8, 0x02, Endian.little);
      bd.setInt32(12, 0x04000, Endian.little);
      for (final (d, v) in [(0, 1), (1, 2), (2, 2), (3, 3)]) {
        bd.setInt32(20 + d * 4, v, Endian.little);
      }
      for (var i = 0; i < 12; i++) {
        bd.setFloat32(68 + i * 4, vals[i], Endian.little);
      }
      final png = decodeGeneratedImage(data);
      final decoded = img.decodePng(png)!;
      expect(decoded.width, 2);
      expect(decoded.height, 2);
      // Expected pixels computed with the reference formula from the SAME
      // float32 values that were encoded (f64→f32 storage rounding matters).
      int px(double v) {
        final f32 = (ByteData(4)..setFloat32(0, v)).getFloat32(0);
        return ((f32 + 1.0) * 127.5).clamp(0.0, 255.0).round();
      }

      final p0 = decoded.getPixel(0, 0);
      expect([p0.r, p0.g, p0.b], [px(vals[0]), px(vals[1]), px(vals[2])]);
      final p3 = decoded.getPixel(1, 1);
      expect([p3.r, p3.g, p3.b], [px(vals[9]), px(vals[10]), px(vals[11])]);
    });
  });

  group('dt_fpzip (requires libfpzip; set FP_FPZIP_LIB)', () {
    final available = DtFpzip.instance.isAvailable;

    test('decompress matches python fpzip', () {
      final stream = hex(
        '66707929870ef0ff0002fd000001fe000001fe000000ff0007da25ca666a287dc7'
        '9ffa3b201001bacdb769f846f55180dbebf400',
      );
      final expected = [
        -1.0, -0.8333333134651184, -0.6666666269302368, -0.5,
        -0.3333333134651184, -0.1666666865348816, 0.0, 0.16666662693023682,
        0.3333333730697632, 0.5, 0.6666666269302368, 0.8333333730697632,
      ];
      final r = DtFpzip.instance.decompress(stream);
      expect((r.nf, r.nz, r.ny, r.nx), (1, 2, 2, 3));
      for (var i = 0; i < expected.length; i++) {
        expect(r.data[i], closeTo(expected[i], 1e-6));
      }
    }, skip: available ? false : 'libfpzip not present in this environment');

    test('decodeGeneratedImage decodes an fpzip NNC payload end to end', () {
      final payload = hex(
        '0100000001000000020000000040000000000000010000000200000002000000'
        '0300000000000000000000000000000000000000000000000000000000000000'
        '0000000066707929870ef0ff0002fd000001fe000001fe000000ff0007da25ca'
        '666a287dc79ffa3b201001bacdb769f846f55180dbebf400',
      );
      final png = decodeGeneratedImage(payload);
      final decoded = img.decodePng(png)!;
      expect(decoded.width, 2);
      expect(decoded.height, 2);
      // Expected pixels from the python golden float values (fpzip is
      // lossless at precision=0, so decode returns numpy's exact f32s).
      const vals = [
        -1.0, -0.8333333134651184, -0.6666666269302368, -0.5,
        -0.3333333134651184, -0.1666666865348816, 0.0, 0.16666662693023682,
        0.3333333730697632, 0.5, 0.6666666269302368, 0.8333333730697632,
      ];
      int px(double v) => ((v + 1.0) * 127.5).clamp(0.0, 255.0).round();
      final p0 = decoded.getPixel(0, 0);
      expect([p0.r, p0.g, p0.b], [px(vals[0]), px(vals[1]), px(vals[2])]);
      final p3 = decoded.getPixel(1, 1);
      expect([p3.r, p3.g, p3.b], [px(vals[9]), px(vals[10]), px(vals[11])]);
    }, skip: available ? false : 'libfpzip not present in this environment');
  });

  group('sanity', () {
    test('embedded CA pem parses as base64 blocks', () {
      // Guards against accidental corruption of the embedded cert constant
      // (checked in-place now — its source file left with the sidecar).
      final pem = DrawThingsNativeClient.caChainPemForTest;
      expect(pem, contains('BEGIN CERTIFICATE'));
      final body = pem
          .replaceAll(RegExp(r'-----(BEGIN|END) CERTIFICATE-----'), '')
          .replaceAll(RegExp(r'\s'), '');
      expect(() => base64.decode(body), returnsNormally);
    });
  });
}
