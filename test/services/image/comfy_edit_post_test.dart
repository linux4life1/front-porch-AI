// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// A Comfy Edit, end to end against a real loopback ComfyUI: the reference
// photo is uploaded, and the graph that is posted names the file ComfyUI
// answered with (not the file it was given), and carries the instruction.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/image/comfy_edit_presets.dart';
import 'package:front_porch_ai/services/image_gen_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

const _stored = 'stored_by_comfy_7.png';

/// An uploaded Edit graph: the photo, the instruction and the model files are
/// placeholders the app fills.
final Map<String, dynamic> _graph = {
  'ckpt': {
    'class_type': 'CheckpointLoaderSimple',
    'inputs': {'ckpt_name': 'edit-model.safetensors'},
  },
  'photo': {
    'class_type': 'LoadImage',
    'inputs': {'image': '%IMAGE%'},
  },
  'pos': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': '%PROMPT%',
      'clip': ['ckpt', 1],
    },
  },
  'neg': {
    'class_type': 'CLIPTextEncode',
    'inputs': {
      'text': '%NEGATIVE%',
      'clip': ['ckpt', 1],
    },
  },
  'latent': {
    'class_type': 'VAEEncode',
    'inputs': {
      'pixels': ['photo', 0],
      'vae': ['ckpt', 2],
    },
  },
  'ks': {
    'class_type': 'KSampler',
    'inputs': {
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
    },
  },
  'decode': {
    'class_type': 'VAEDecode',
    'inputs': {
      'samples': ['ks', 0],
      'vae': ['ckpt', 2],
    },
  },
  'save': {
    'class_type': 'SaveImage',
    'inputs': {
      'images': ['decode', 0],
      'filename_prefix': 'fpai',
    },
  },
};

class _Comfy {
  final List<int> uploaded = [];
  String? uploadedName;
  int uploads = 0;
  Map<String, dynamic>? posted;
  late final HttpServer server;
}

Future<_Comfy> _serve() async {
  final comfy = _Comfy();
  comfy.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  comfy.server.listen((request) async {
    final path = request.uri.path;
    request.response.headers.contentType = ContentType.json;
    if (path == '/object_info') {
      request.response.write(
        jsonEncode({
          for (final n in _graph.values)
            (n as Map)['class_type'].toString(): <String, dynamic>{},
        }),
      );
    } else if (request.method == 'POST' && path == '/upload/image') {
      comfy.uploads++;
      final bytes = BytesBuilder();
      await for (final chunk in request) {
        bytes.add(chunk);
      }
      comfy.uploaded.addAll(bytes.takeBytes());
      request.response.write(jsonEncode({'name': _stored, 'subfolder': ''}));
    } else if (request.method == 'POST' && path == '/prompt') {
      final body = jsonDecode(await utf8.decodeStream(request)) as Map;
      comfy.posted = (body['prompt'] as Map).cast<String, dynamic>();
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('stop');
    } else {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.notFound;
    }
    await request.response.close();
  });
  return comfy;
}

void main() {
  setUp(() => HttpOverrides.global = null);

  test(
    'the photo is uploaded and the posted graph names what ComfyUI stored',
    () async {
      final comfy = await _serve();
      addTearDown(() => comfy.server.close(force: true));
      final dir = Directory.systemTemp.createTempSync('comfy-edit-post');
      addTearDown(() => dir.deleteSync(recursive: true));
      final storage = StorageService.sandbox(dir.path);
      final s = storage.imageGenSettings;
      await s.setImageGenBackend('comfyui');
      await s.setComfyUiUrl('http://127.0.0.1:${comfy.server.port}');
      await s.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
      await s.setComfyEditUploadedWorkflow(jsonEncode(_graph));
      await s.setImageGenEditModel('edit-model.safetensors');
      final photo = Uint8List.fromList(List<int>.generate(64, (i) => 250 - i));
      final image = ImageGenService(storage);

      await image.generateImage(
        prompt: 'make it night',
        referenceImage: photo,
        intent: StudioIntent.edit,
      );

      expect(comfy.posted, isNotNull, reason: image.statusMessage);
      expect(comfy.uploads, 1);
      // The photo's own bytes reached ComfyUI, whole.
      expect(latin1.decode(comfy.uploaded), contains(latin1.decode(photo)));
      final posted = comfy.posted!;
      expect((posted['photo'] as Map)['inputs']['image'], _stored);
      expect((posted['pos'] as Map)['inputs']['text'], 'make it night');
      expect(jsonEncode(posted), isNot(contains('%')));
    },
  );

  test('with no photo nothing is uploaded and nothing is posted', () async {
    final comfy = await _serve();
    addTearDown(() => comfy.server.close(force: true));
    final dir = Directory.systemTemp.createTempSync('comfy-edit-post');
    addTearDown(() => dir.deleteSync(recursive: true));
    final storage = StorageService.sandbox(dir.path);
    final s = storage.imageGenSettings;
    await s.setImageGenBackend('comfyui');
    await s.setComfyUiUrl('http://127.0.0.1:${comfy.server.port}');
    await s.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
    await s.setComfyEditUploadedWorkflow(jsonEncode(_graph));
    await s.setImageGenEditModel('edit-model.safetensors');

    await ImageGenService(
      storage,
    ).generateImage(prompt: 'make it night', intent: StudioIntent.edit);

    expect(comfy.uploads, 0);
    expect(
      comfy.posted?.values.any(
        (n) =>
            (n as Map)['class_type'] == 'LoadImage' &&
            (n['inputs']['image'] == _stored),
      ),
      isNot(true),
    );
  });
}
