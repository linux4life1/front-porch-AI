// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Unit tests for the pure image-reference capability seam — the routing
// rewrite-proofing. Pins the (backend × model × intent × refCount × comfy-nodes)
// matrix so a future edit-model family can't silently break it.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/capability/image_reference_role.dart';
import 'package:front_porch_ai/services/capability/image_reference_resolver.dart';
import 'package:front_porch_ai/services/image_gen_service.dart'
    show ImageGenBackend;

void main() {
  group('detectEditModel (local name heuristics)', () {
    test('Flux Kontext names → kontext', () {
      expect(detectEditModel('flux1-kontext-dev'), EditModelKind.kontext);
      expect(detectEditModel('FLUX.1-Kontext-Q8.gguf'), EditModelKind.kontext);
    });

    test('names carrying both qwen and edit → qwenEdit', () {
      expect(detectEditModel('qwen_image_edit_2509_f16.ckpt'),
          EditModelKind.qwenEdit);
      expect(detectEditModel('Qwen-Image-Edit-2511'), EditModelKind.qwenEdit);
    });

    test('plain checkpoints are NOT edit models', () {
      expect(detectEditModel('qwen_image_1.0_q6p.ckpt'), EditModelKind.none);
      expect(detectEditModel('flux1-dev'), EditModelKind.none);
      expect(detectEditModel('juggernautXL_v9.safetensors'),
          EditModelKind.none);
      expect(detectEditModel('sd_xl_base_1.0'), EditModelKind.none);
      expect(detectEditModel(''), EditModelKind.none);
    });

    test('a merely renamed/"edited" Qwen checkpoint does NOT false-positive', () {
      expect(detectEditModel('qwen_image_edited_v2'), EditModelKind.none);
      expect(detectEditModel('qwen_image_1.0_hand-edited.ckpt'),
          EditModelKind.none);
    });
  });

  group('remoteEditSpec (id allowlist)', () {
    test('known edit ids resolve with their caps', () {
      expect(remoteEditSpec('qwen-image-max-edit'),
          (kind: EditModelKind.qwenEdit, maxImages: kQwenEditMaxImages));
      expect(remoteEditSpec('gpt-image-2'),
          (kind: EditModelKind.generic, maxImages: 16));
      expect(remoteEditSpec('glm-image-edit'),
          (kind: EditModelKind.generic, maxImages: 1));
    });

    test('unknown "*-edit" ids fall back to a single-image edit', () {
      expect(remoteEditSpec('some-future-provider-edit'),
          (kind: EditModelKind.generic, maxImages: 1));
    });

    test('segment-style "edit" ids from the live Nano-GPT list resolve', () {
      // Verified against Nano-GPT /image-models (path-style + suffixed ids).
      for (final id in const [
        'bytedance/seedream-v5.0-pro/edit',
        'pruna-ai/p-image/edit',
        'microsoft/mai-image-2.5/edit',
        'fal-ai/bernini-r/edit-image',
        'step-image-edit-2',
        'nano-banana-edit',
        'nano-banana-pro-edit',
      ]) {
        expect(remoteEditSpec(id), (kind: EditModelKind.generic, maxImages: 1),
            reason: id);
      }
    });

    test('case-insensitive; non-edit ids → null', () {
      expect(remoteEditSpec('QWEN-IMAGE-MAX-EDIT')?.kind,
          EditModelKind.qwenEdit);
      expect(remoteEditSpec('qwen-image-max'), isNull);
      expect(remoteEditSpec('flux-1-dev'), isNull);
      expect(remoteEditSpec('dall-e-3'), isNull);
    });

    test('real non-edit catalog ids never match (no suffix false positives)', () {
      // These live in the remote model catalog; none is an edit model.
      for (final id in const [
        'ideogram-v3-remove-text',
        'seedream-v5.0-lite-sequential',
        'qwen-image-max',
        'bria-fibo',
        'hunyuan-image-3-instruct',
        'ideogram-v3-generate-transparent',
      ]) {
        expect(remoteEditSpec(id), isNull, reason: id);
      }
    });
  });

  group('resolveCapability (pure matrix)', () {
    test('Draw-Things-like: qwen edit, backend cap 1 → edit x1', () {
      final cap = resolveCapability(
        modelName: 'qwen_image_edit_2509.ckpt',
        backendSupportsImg2img: true,
        backendEditMaxImages: kDrawThingsEditMaxImages,
      );
      expect(cap.supportsEdit, isTrue);
      expect(cap.editKind, EditModelKind.qwenEdit);
      expect(cap.editMaxImages, 1); // min(model 3, backend 1)
      expect(cap.supportsImg2img, isTrue);
      expect(cap.degradeReason, isNull);
    });

    test('ComfyUI-like: qwen edit + nodes present → edit x3', () {
      final cap = resolveCapability(
        modelName: 'qwen-image-edit-2509',
        backendSupportsImg2img: true,
        backendEditMaxImages: 64,
        requireComfyEditNodes: true,
        comfyEditNodesAvailable: true,
      );
      expect(cap.supportsEdit, isTrue);
      expect(cap.editMaxImages, kQwenEditMaxImages); // 3
    });

    test('ComfyUI-like: edit model but nodes missing → unsupported, reason', () {
      final cap = resolveCapability(
        modelName: 'qwen-image-edit-2509',
        backendSupportsImg2img: true,
        backendEditMaxImages: 64,
        requireComfyEditNodes: true,
        comfyEditNodesAvailable: false,
      );
      expect(cap.supportsEdit, isFalse);
      expect(cap.editMaxImages, 0);
      expect(cap.editKind, EditModelKind.qwenEdit); // still detected
      expect(cap.degradeReason, contains('edit nodes'));
    });

    test('Kontext caps at a single reference even on a wide backend', () {
      final cap = resolveCapability(
        modelName: 'flux1-kontext-dev',
        backendSupportsImg2img: true,
        backendEditMaxImages: 64,
      );
      expect(cap.supportsEdit, isTrue);
      expect(cap.editMaxImages, kKontextEditMaxImages); // 1
    });

    test('non-edit model → no edit, "switch to" reason, img2img intact', () {
      final cap = resolveCapability(
        modelName: 'juggernautXL_v9',
        backendSupportsImg2img: true,
        backendEditMaxImages: 64,
      );
      expect(cap.supportsEdit, isFalse);
      expect(cap.editKind, EditModelKind.none);
      expect(cap.supportsImg2img, isTrue);
      expect(cap.degradeReason, contains('Switch to'));
    });

    test('A1111 gate: even an edit-named model gets no edit when backend cap 0',
        () {
      final cap = resolveCapability(
        modelName: 'qwen_image_edit_2509', // edit name…
        backendSupportsImg2img: true,
        backendEditMaxImages: 0, // …but A1111 can't edit-condition
      );
      expect(cap.supportsEdit, isFalse);
      expect(cap.editMaxImages, 0);
      expect(cap.degradeReason, contains('backend can’t run edit'));
      expect(cap.supportsImg2img, isTrue); // Create/img2img still works
    });

    test('remote allowlist path: qwen edit id → edit x3, no img2img', () {
      final cap = resolveCapability(
        modelName: 'qwen-image-max-edit',
        backendSupportsImg2img: false,
        backendEditMaxImages: 64,
        useRemoteAllowlist: true,
      );
      expect(cap.supportsEdit, isTrue);
      expect(cap.editKind, EditModelKind.qwenEdit);
      expect(cap.editMaxImages, kQwenEditMaxImages);
      expect(cap.supportsImg2img, isFalse);
    });

    test('remote non-edit id → no edit', () {
      final cap = resolveCapability(
        modelName: 'flux-1-dev',
        backendSupportsImg2img: false,
        backendEditMaxImages: 64,
        useRemoteAllowlist: true,
      );
      expect(cap.supportsEdit, isFalse);
      expect(cap.editKind, EditModelKind.none);
    });

    test('derived-field invariant holds for every resolved capability', () {
      final caps = [
        // edit-capable
        resolveCapability(
            modelName: 'qwen-image-edit-2509',
            backendSupportsImg2img: true,
            backendEditMaxImages: 64),
        // off: non-edit model
        resolveCapability(
            modelName: 'sd_xl_base',
            backendSupportsImg2img: true,
            backendEditMaxImages: 64),
        // off: backend cap 0 (A1111)
        resolveCapability(
            modelName: 'qwen-image-edit-2509',
            backendSupportsImg2img: true,
            backendEditMaxImages: 0),
        // off: comfy nodes missing
        resolveCapability(
            modelName: 'qwen-image-edit-2509',
            backendSupportsImg2img: true,
            backendEditMaxImages: 64,
            requireComfyEditNodes: true,
            comfyEditNodesAvailable: false),
      ];
      for (final c in caps) {
        expect(c.supportsEdit, c.editMaxImages > 0, reason: c.toString());
        expect(c.supportsEdit, c.degradeReason == null, reason: c.toString());
      }
    });
  });

  group('routeReference (fail-closed contract)', () {
    const editable = ImageReferenceCapability(
      supportsEdit: true,
      editMaxImages: 3,
      supportsImg2img: true,
      editKind: EditModelKind.qwenEdit,
    );
    const noEdit = ImageReferenceCapability(
      supportsEdit: false,
      editMaxImages: 0,
      supportsImg2img: true,
      editKind: EditModelKind.none,
      degradeReason: 'nope',
    );
    const remoteNoImg2img = ImageReferenceCapability(
      supportsEdit: false,
      editMaxImages: 0,
      supportsImg2img: false,
      editKind: EditModelKind.none,
    );

    test('edit + capable + a reference → editConditioning', () {
      expect(
        routeReference(
            intent: StudioIntent.edit, attachedRefCount: 1, cap: editable),
        ImageReferenceRole.editConditioning,
      );
    });

    test('edit + capable + no reference → inert none (UI-guarded)', () {
      expect(
        routeReference(
            intent: StudioIntent.edit, attachedRefCount: 0, cap: editable),
        ImageReferenceRole.none,
      );
    });

    test('edit + NOT capable → unsupported, NEVER img2img (even with a ref)',
        () {
      expect(
        routeReference(
            intent: StudioIntent.edit, attachedRefCount: 1, cap: noEdit),
        ImageReferenceRole.unsupported,
      );
    });

    test('create + a reference + img2img → img2imgDenoise', () {
      expect(
        routeReference(
            intent: StudioIntent.create, attachedRefCount: 1, cap: editable),
        ImageReferenceRole.img2imgDenoise,
      );
    });

    test('create + a reference but no img2img (remote) → none', () {
      expect(
        routeReference(
            intent: StudioIntent.create,
            attachedRefCount: 1,
            cap: remoteNoImg2img),
        ImageReferenceRole.none,
      );
    });

    test('create + no reference → none (txt2img)', () {
      expect(
        routeReference(
            intent: StudioIntent.create, attachedRefCount: 0, cap: editable),
        ImageReferenceRole.none,
      );
    });

    test('over-count (UI failed to clamp) still routes editConditioning', () {
      // Contract: attachedRefCount is UI-clamped to editMaxImages. Even if a
      // caller passes more, the ROLE is unchanged — payload-size clamping is the
      // generate layer's job, not the router's.
      const cap1 = ImageReferenceCapability(
        supportsEdit: true,
        editMaxImages: 1,
        supportsImg2img: true,
        editKind: EditModelKind.kontext,
      );
      expect(
        routeReference(
            intent: StudioIntent.edit, attachedRefCount: 5, cap: cap1),
        ImageReferenceRole.editConditioning,
      );
    });
  });

  group('ImageReferenceResolver adapter (current rollout)', () {
    test('A1111: img2img on, edit off', () {
      final cap = ImageReferenceResolver.resolveForBackend(
        backend: ImageGenBackend.a1111,
        modelName: 'qwen_image_edit_2509',
      );
      expect(cap.supportsEdit, isFalse);
      expect(cap.supportsImg2img, isTrue);
    });

    test('Draw Things + qwen edit: edit on, capped at 1 today', () {
      final cap = ImageReferenceResolver.resolveForBackend(
        backend: ImageGenBackend.drawThings,
        modelName: 'qwen_image_edit_2509.ckpt',
      );
      expect(cap.supportsEdit, isTrue);
      expect(cap.editMaxImages, 1);
    });

    test('Draw Things + plain checkpoint: img2img only', () {
      final cap = ImageReferenceResolver.resolveForBackend(
        backend: ImageGenBackend.drawThings,
        modelName: 'juggernautXL_v9',
      );
      expect(cap.supportsEdit, isFalse);
      expect(cap.supportsImg2img, isTrue);
    });

    test('ComfyUI edit is ON (preset-driven, any model)', () {
      // ComfyUI edits via a SELECTED workflow (preset or uploaded), not a
      // detected model name — so edit is offered for ANY model when the backend
      // is ComfyUI (fine readiness is checked in the Edit tab). Single reference.
      final comfy = ImageReferenceResolver.resolveForBackend(
        backend: ImageGenBackend.comfyUi,
        modelName: 'anything-at-all',
      );
      expect(comfy.supportsEdit, isTrue);
      expect(comfy.editMaxImages, 1);
      expect(comfy.editKind, EditModelKind.generic);
      expect(comfy.supportsImg2img, isTrue);
      expect(comfy.degradeReason, isNull);
    });

    test('remote edit is ON for an allowlisted edit model (single image, no '
        'img2img); a non-edit remote model degrades', () {
      final edit = ImageReferenceResolver.resolveForBackend(
        backend: ImageGenBackend.remote,
        modelName: 'qwen-image-max-edit',
      );
      expect(edit.supportsEdit, isTrue);
      expect(edit.editMaxImages, 1); // capped at one reference
      expect(edit.supportsImg2img, isFalse); // remote never does classic img2img
      expect(edit.degradeReason, isNull);

      final plain = ImageReferenceResolver.resolveForBackend(
        backend: ImageGenBackend.remote,
        modelName: 'gpt-4o', // not an image-edit model
      );
      expect(plain.supportsEdit, isFalse);
      expect(plain.degradeReason, isNotNull);
    });
  });

  group('ImageReferenceCapability value semantics', () {
    test('equality + hashCode', () {
      const a = ImageReferenceCapability(
        supportsEdit: true,
        editMaxImages: 3,
        supportsImg2img: true,
        editKind: EditModelKind.qwenEdit,
      );
      const b = ImageReferenceCapability(
        supportsEdit: true,
        editMaxImages: 3,
        supportsImg2img: true,
        editKind: EditModelKind.qwenEdit,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });
  });
}
