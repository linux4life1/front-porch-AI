// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Edit on the phone really edits: the picture it is given reaches ComfyUI and
// the graph that is posted is the Edit graph with the instruction in it. A
// Create with no picture runs the Create graph. The picture is checked before
// anything is sent to ComfyUI.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/image/image.dart'
    show kComfyUploadedWorkflowId;
import 'package:front_porch_ai/services/web/facade/image_facade.dart'
    show kMaxDeskPictureBytes;

import 'image_desk_harness.dart';

Map<String, dynamic> _node(String type, Map<String, dynamic> inputs) => {
  'class_type': type,
  'inputs': inputs,
};

/// An uploaded Edit graph: a photo, an instruction, and a model file.
final Map<String, dynamic> _editGraph = {
  'ckpt': _node('CheckpointLoaderSimple', {
    'ckpt_name': 'edit-model.safetensors',
  }),
  'photo': _node('LoadImage', {'image': '%IMAGE%'}),
  'pos': _node('CLIPTextEncode', {
    'text': '%PROMPT%',
    'clip': ['ckpt', 1],
  }),
  'neg': _node('CLIPTextEncode', {
    'text': '%NEGATIVE%',
    'clip': ['ckpt', 1],
  }),
  'latent': _node('VAEEncode', {
    'pixels': ['photo', 0],
    'vae': ['ckpt', 2],
  }),
  'ks': _node('KSampler', {
    'model': ['ckpt', 0],
    'positive': ['pos', 0],
    'negative': ['neg', 0],
    'latent_image': ['latent', 0],
    'seed': '%SEED%',
    'steps': '%STEPS%',
    'cfg': '%CFG%',
    'sampler_name': 'euler',
    'scheduler': 'normal',
    'denoise': '%DENOISE%',
  }),
  'decode': _node('VAEDecode', {
    'samples': ['ks', 0],
    'vae': ['ckpt', 2],
  }),
  'save': _node('SaveImage', {
    'images': ['decode', 0],
    'filename_prefix': 'fpai',
  }),
};

/// An uploaded Create graph: no photo.
final Map<String, dynamic> _createGraph = {
  'ckpt': _node('CheckpointLoaderSimple', {
    'ckpt_name': 'create-model.safetensors',
  }),
  'pos': _node('CLIPTextEncode', {
    'text': '%PROMPT%',
    'clip': ['ckpt', 1],
  }),
  'neg': _node('CLIPTextEncode', {
    'text': '%NEGATIVE%',
    'clip': ['ckpt', 1],
  }),
  'latent': _node('EmptyLatentImage', {
    'width': '%WIDTH%',
    'height': '%HEIGHT%',
    'batch_size': 1,
  }),
  'ks': _node('KSampler', {
    'model': ['ckpt', 0],
    'positive': ['pos', 0],
    'negative': ['neg', 0],
    'latent_image': ['latent', 0],
    'seed': '%SEED%',
    'steps': '%STEPS%',
    'cfg': '%CFG%',
    'sampler_name': 'euler',
    'scheduler': 'normal',
    'denoise': 1,
  }),
  'decode': _node('VAEDecode', {
    'samples': ['ks', 0],
    'vae': ['ckpt', 2],
  }),
  'save': _node('SaveImage', {
    'images': ['decode', 0],
    'filename_prefix': 'fpai',
  }),
};

List<int> _picture() => img.encodePng(img.Image(width: 3, height: 3));

String _dataUrl(List<int> bytes) =>
    'data:image/png;base64,${base64Encode(bytes)}';

bool _hasPhotoNode(Map<String, dynamic>? graph) =>
    graph?.values.any((n) => n is Map && n['class_type'] == 'LoadImage') ??
    false;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DeskComfy comfy;
  late DeskHarness h;

  setUp(() async {
    comfy = await DeskComfy.start();
    h = await DeskHarness.boot(comfy: comfy);
    final s = h.settings;
    await s.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
    await s.setComfyEditUploadedWorkflow(jsonEncode(_editGraph));
    await s.setImageGenEditModel('edit-model.safetensors');
    await s.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
    await s.setComfyCreateUploadedWorkflow(jsonEncode(_createGraph));
    await s.setImageGenModel('create-model.safetensors');
  });

  test(
    'the picture reaches ComfyUI and the Edit graph is what is posted',
    () async {
      final photo = _picture();

      await h.call('POST', '/api/image/generate', {
        'prompt': 'make it night',
        'mode': 'edit',
        'referenceImage': _dataUrl(photo),
      });

      expect(comfy.uploads, 1);
      expect(latin1.decode(comfy.uploaded), contains(latin1.decode(photo)));
      final posted = comfy.posted;
      expect(posted, isNotNull, reason: h.image.statusMessage);
      expect((posted!['photo'] as Map)['inputs']['image'], DeskComfy.stored);
      expect((posted['pos'] as Map)['inputs']['text'], 'make it night');
    },
  );

  test('a picture this app saved can be edited by its file name', () async {
    final images = Directory(
      p.join(h.storage.rootPath!, 'KoboldManager', 'images'),
    )..createSync(recursive: true);
    final photo = _picture();
    File(p.join(images.path, 'saved_1.png')).writeAsBytesSync(photo);

    await h.call('POST', '/api/image/generate', {
      'prompt': 'add a hat',
      'mode': 'edit',
      'referenceFilename': 'saved_1.png',
    });

    expect(comfy.uploads, 1);
    expect(latin1.decode(comfy.uploaded), contains(latin1.decode(photo)));
    expect((comfy.posted!['pos'] as Map)['inputs']['text'], 'add a hat');
  });

  test('Edit with no picture asks for one and sends nothing', () async {
    final (status, body) = await h.call('POST', '/api/image/generate', {
      'prompt': 'make it night',
      'mode': 'edit',
    });

    expect(status, 400);
    expect(body['code'], 'needs_picture');
    expect(comfy.uploads, 0);
    expect(comfy.posted, isNull);
  });

  test('Create runs the Create graph, not the Edit one', () async {
    await h.call('POST', '/api/image/generate', {'prompt': 'a quiet porch'});

    expect(comfy.uploads, 0);
    final posted = comfy.posted;
    expect(posted, isNotNull, reason: h.image.statusMessage);
    expect(_hasPhotoNode(posted), isFalse);
    expect((posted!['pos'] as Map)['inputs']['text'], 'a quiet porch');
  });

  group('the picture is checked before anything is sent', () {
    Future<void> expectRefused(
      Map<String, dynamic> body,
      int status,
      String code,
    ) async {
      final (got, answer) = await h.call('POST', '/api/image/generate', {
        'prompt': 'make it night',
        'mode': 'edit',
        ...body,
      });
      expect(got, status, reason: '$body');
      expect(answer['code'], code, reason: '$body');
      expect(comfy.uploads, 0);
      expect(comfy.posted, isNull);
    }

    test('something that is not a picture', () async {
      await expectRefused(
        {'referenceImage': _dataUrl(utf8.encode('just some words here'))},
        400,
        'bad_picture',
      );
      await expectRefused(
        {'referenceImage': 'not a data url'},
        400,
        'bad_picture',
      );
      await expectRefused(
        {'referenceImage': 'data:image/png;base64,@@@@'},
        400,
        'bad_picture',
      );
    });

    test('a saved picture that is not there', () async {
      await expectRefused({'referenceFilename': 'gone.png'}, 404, 'no_picture');
      await expectRefused(
        {'referenceFilename': '../../etc/passwd'},
        404,
        'no_picture',
      );
    });

    test('a saved picture that is too large', () async {
      final images = Directory(
        p.join(h.storage.rootPath!, 'KoboldManager', 'images'),
      )..createSync(recursive: true);
      File(
        p.join(images.path, 'huge.png'),
      ).writeAsBytesSync(List<int>.filled(kMaxDeskPictureBytes + 1, 0));

      await expectRefused({'referenceFilename': 'huge.png'}, 413, 'too_large');
    });

    test('a picture that is too large', () async {
      final big = List<int>.filled(kMaxDeskPictureBytes + 1024, 0)
        ..setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
      await expectRefused({'referenceImage': _dataUrl(big)}, 413, 'too_large');
    });
  });
}
