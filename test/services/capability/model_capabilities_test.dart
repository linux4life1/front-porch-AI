// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/utils/gguf_vision.dart';

void main() {
  group('ModelApiCapabilities.fromOpenRouterEntry', () {
    test('reads vision from architecture.input_modalities', () {
      final caps = ModelApiCapabilities.fromOpenRouterEntry({
        'id': 'anthropic/claude-3.5-sonnet',
        'architecture': {
          'input_modalities': ['text', 'image'],
          'output_modalities': ['text'],
        },
        'supported_parameters': ['tools', 'temperature'],
      });
      expect(caps.vision, isTrue);
      expect(caps.toolCalling, isTrue);
    });

    test('text-only model has neither vision nor tools', () {
      final caps = ModelApiCapabilities.fromOpenRouterEntry({
        'id': 'some/text-model',
        'architecture': {
          'input_modalities': ['text'],
        },
        'supported_parameters': ['temperature', 'top_p'],
      });
      expect(caps.vision, isFalse);
      expect(caps.toolCalling, isFalse);
    });

    test('tolerates missing/malformed fields', () {
      final caps = ModelApiCapabilities.fromOpenRouterEntry({'id': 'x'});
      expect(caps.vision, isFalse);
      expect(caps.toolCalling, isFalse);
    });
  });

  group('ModelApiCapabilities.fromNanoGptEntry', () {
    test('reads capabilities.vision and tool_calling', () {
      final caps = ModelApiCapabilities.fromNanoGptEntry({
        'id': 'gpt-4o',
        'capabilities': {'vision': true, 'tool_calling': true},
      });
      expect(caps.vision, isTrue);
      expect(caps.toolCalling, isTrue);
    });

    test('false capabilities parse to false', () {
      final caps = ModelApiCapabilities.fromNanoGptEntry({
        'id': 'text-only',
        'capabilities': {'vision': false, 'tool_calling': false},
      });
      expect(caps.vision, isFalse);
      expect(caps.toolCalling, isFalse);
    });

    test('missing capabilities object defaults to false', () {
      final caps = ModelApiCapabilities.fromNanoGptEntry({'id': 'basic'});
      expect(caps.vision, isFalse);
      expect(caps.toolCalling, isFalse);
    });
  });

  group('ModelApiCapabilities.fromLmStudioEntry', () {
    test('type "vlm" means vision (how LM Studio marks its eye icon)', () {
      final caps = ModelApiCapabilities.fromLmStudioEntry({
        'id': 'google/gemma-4-12b-qat',
        'type': 'vlm',
        'state': 'loaded',
      });
      expect(caps.vision, isTrue);
    });

    test('capabilities list is honored on newer builds', () {
      final caps = ModelApiCapabilities.fromLmStudioEntry({
        'id': 'some/vision-model',
        'type': 'llm', // older field disagrees; capabilities wins
        'capabilities': ['vision', 'tool_use'],
      });
      expect(caps.vision, isTrue);
      expect(caps.toolCalling, isTrue);
    });

    test('plain text model has neither', () {
      final caps = ModelApiCapabilities.fromLmStudioEntry({
        'id': 'text-model',
        'type': 'llm',
        'capabilities': <String>[],
      });
      expect(caps.vision, isFalse);
      expect(caps.toolCalling, isFalse);
    });

    test('tolerates missing/malformed fields', () {
      final caps = ModelApiCapabilities.fromLmStudioEntry({'id': 'x'});
      expect(caps.vision, isFalse);
      expect(caps.toolCalling, isFalse);
    });
  });

  group('originEndpointUri', () {
    test('replaces a trailing /v1 with the extension path (LM Studio)', () {
      expect(
        originEndpointUri(
          'http://localhost:1234/v1',
          'api/v0/models',
        ).toString(),
        'http://localhost:1234/api/v0/models',
      );
    });

    test('derives the oMLX status endpoint (keeps its /v1 prefix)', () {
      expect(
        originEndpointUri(
          'http://localhost:8000/v1',
          'v1/models/status',
        ).toString(),
        'http://localhost:8000/v1/models/status',
      );
    });

    test('handles trailing slash and no /v1 suffix', () {
      expect(
        originEndpointUri(
          'http://localhost:1234/v1/',
          'api/v0/models',
        ).toString(),
        'http://localhost:1234/api/v0/models',
      );
      expect(
        originEndpointUri(
          'http://192.168.1.5:1234',
          'api/v0/models',
        ).toString(),
        'http://192.168.1.5:1234/api/v0/models',
      );
    });

    test('unparseable / schemeless input returns null', () {
      expect(originEndpointUri('', 'api/v0/models'), isNull);
      expect(originEndpointUri('localhost:1234', 'api/v0/models'), isNull);
    });
  });

  group('omlxCapabilitiesFromStatusEntry (tri-state)', () {
    test('engine_type vlm → vision', () {
      final caps = omlxCapabilitiesFromStatusEntry({
        'id': 'mlx-community/Qwen2-VL-7B',
        'engine_type': 'vlm',
        'loaded': true,
      });
      expect(caps, isNotNull);
      expect(caps!.vision, isTrue);
    });

    test('engine_type llm → definitively no vision', () {
      final caps = omlxCapabilitiesFromStatusEntry({
        'id': 'mlx-community/Llama-3-8B',
        'engine_type': 'llm',
      });
      expect(caps, isNotNull);
      expect(caps!.vision, isFalse);
    });

    test('no type signal → null (caller must fall through to probe, '
        'never conclude "no vision")', () {
      expect(omlxCapabilitiesFromStatusEntry({'id': 'x'}), isNull);
      expect(
        omlxCapabilitiesFromStatusEntry({'id': 'x', 'engine_type': 'jang'}),
        isNull,
      );
    });
  });

  group('VisionSupport.unknown', () {
    test('is unsupported for consumers but distinct from none', () {
      expect(VisionSupport.unknown.supported, isFalse);
      expect(VisionSupport.unknown.source, VisionSource.unknown);
      expect(VisionSupport.unknown.source, isNot(VisionSource.none));
    });
  });

  group('VisionSupport.fromApi', () {
    test('vision-capable caps → supported via apiMetadata', () {
      final s = VisionSupport.fromApi(const ModelApiCapabilities(vision: true));
      expect(s.supported, isTrue);
      expect(s.source, VisionSource.apiMetadata);
    });

    test('null or non-vision caps → none', () {
      expect(VisionSupport.fromApi(null).supported, isFalse);
      expect(
        VisionSupport.fromApi(const ModelApiCapabilities()).source,
        VisionSource.none,
      );
    });
  });

  group('VisionSupport.fromGguf', () {
    GgufVisionInfo info({
      bool embedded = false,
      bool multimodal = false,
      String arch = 'llama',
    }) => GgufVisionInfo(
      architecture: arch,
      hasEmbeddedProjector: embedded,
      isMultimodal: multimodal,
    );

    test('embedded projector → supported (ggufEmbedded)', () {
      final s = VisionSupport.fromGguf(
        info(embedded: true, multimodal: true),
        mmprojConfigured: false,
      );
      expect(s.supported, isTrue);
      expect(s.source, VisionSource.ggufEmbedded);
    });

    test('multimodal + mmproj configured → supported (ggufWithMmproj)', () {
      final s = VisionSupport.fromGguf(
        info(multimodal: true),
        mmprojConfigured: true,
      );
      expect(s.supported, isTrue);
      expect(s.source, VisionSource.ggufWithMmproj);
    });

    test('multimodal without mmproj → not supported', () {
      final s = VisionSupport.fromGguf(
        info(multimodal: true),
        mmprojConfigured: false,
      );
      expect(s.supported, isFalse);
      expect(s.source, VisionSource.none);
    });

    test('not-detected-as-vision arch WITHOUT mmproj → not supported', () {
      final s = VisionSupport.fromGguf(info(), mmprojConfigured: false);
      expect(s.supported, isFalse);
    });

    test('UNPARSEABLE gguf (info == null) + attached mmproj → still supported '
        '(the browsed projector is authoritative)', () {
      // Regression (community report 2026-07-14): resolveLocalGgufInfo nulls
      // on any parser exception and caches it, and the old null-first
      // bail-out then discarded the user's browsed mmproj — the app refused
      // to send images while the launch path had loaded the projector and
      // the server could genuinely see. A parse failure must never silence
      // an explicit user attachment.
      final s = VisionSupport.fromGguf(null, mmprojConfigured: true);
      expect(s.supported, isTrue);
      expect(s.source, VisionSource.ggufWithMmproj);
    });

    test('unparseable gguf without mmproj → not supported', () {
      final s = VisionSupport.fromGguf(null, mmprojConfigured: false);
      expect(s.supported, isFalse);
    });

    test('an attached mmproj is authoritative even when the arch heuristic '
        'says text-only → supported (ggufWithMmproj)', () {
      // Regression: users with a companion mmproj for a model our conservative
      // arch allowlist doesn't recognize (finetunes, renamed arches) must be
      // able to enable vision. The explicit mmproj is trusted regardless of
      // isMultimodal.
      final s = VisionSupport.fromGguf(info(), mmprojConfigured: true);
      expect(s.supported, isTrue);
      expect(s.source, VisionSource.ggufWithMmproj);
    });

  });

  group('capability metadata host detection (shared helper)', () {
    test('OpenRouter and Nano-GPT hosts are metadata providers', () {
      expect(
        isCapabilityMetadataProviderUrl('https://openrouter.ai/api/v1'),
        isTrue,
      );
      expect(
        isCapabilityMetadataProviderUrl('https://nano-gpt.com/api/v1'),
        isTrue,
      );
      expect(
        isCapabilityMetadataProviderUrl('HTTPS://NANO-GPT.com/API/v1'),
        isTrue,
      );
    });

    test('generic remotes, oMLX, and localhost are not', () {
      expect(
        isCapabilityMetadataProviderUrl('http://localhost:8000/v1'),
        isFalse,
      );
      expect(
        isCapabilityMetadataProviderUrl('http://192.168.1.20:1234/v1'),
        isFalse,
      );
      expect(
        isCapabilityMetadataProviderUrl('https://api.openai.com/v1'),
        isFalse,
      );
      expect(isCapabilityMetadataProviderUrl(''), isFalse);
    });

    test('only Nano-GPT needs the detailed models request', () {
      expect(isNanoGptUrl('https://nano-gpt.com/api/v1'), isTrue);
      expect(isNanoGptUrl('https://openrouter.ai/api/v1'), isFalse);
    });
  });
}
