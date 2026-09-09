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

part of 'image_gen_service.dart';

/// Cluster A — generation orchestration. generateImage() itself is
/// fake-pinned (three protected test fakes `implements ImageGenService`
/// override it), so the shell keeps a one-line forwarding stub with the
/// original doc comment + signature; this extension holds the verbatim body.
extension _ImageGenGenerate on ImageGenService {
  // Verbatim body of the old generateImage — see the shell's public stub
  // (same name, no Impl suffix) for the doc comment and signature.
  Future<Uint8List?> _generateImageImpl({
    required String prompt,
    String? negativePrompt,
    String? size,
    Uint8List?
    referenceImage, // img2img reference: honored by all three local backends
    // (Draw Things, A1111, ComfyUI) at imageGenDenoise strength; remote APIs
    // have no img2img endpoint here, so they ignore it.
    String? model,
    bool isPortrait = false,
    // Per-call overrides for the stored seed/denoise settings; used by batch
    // flows (expression packs) that need a shared fixed seed and fixed denoise
    // across every image without touching the user's persisted settings.
    // Remote APIs ignore them (no seed/denoise support on those endpoints).
    int? seed,
    double? denoise,
    // Which surface asked. Create (default) keeps every existing path
    // byte-identical; Edit routes an edit-capable model to edit-conditioning
    // and resolves the EDIT model slot. Passed by the Studio's Edit tab and
    // by edit-first expression packs (Studio dialog + the creator panel).
    StudioIntent intent = StudioIntent.create,
    // Edit-only: how strongly the instruction changes the reference (higher =
    // more change). Overrides the edit profile's default strength when set, so
    // the Edit tab can offer a "how much should change" control. Ignored outside
    // the edit path.
    double? editStrength,
  }) async {
    // Reentrancy guard: this service holds a SINGLE shared _isGenerating /
    // _statusMessage / _genPreview / _genProgress. Two overlapping calls (the
    // classic case: the WebUI image panel + the desktop Studio, or /image while
    // a Studio gen runs) would clobber each other's status and progress, the
    // first to finish would flip _isGenerating false and unlock the other
    // mid-flight, and on Draw Things both would spawn CLI jobs against one GPU.
    // Refuse the second start rather than corrupt the first.
    if (_isGenerating) {
      debugPrint('[ImageGen] generateImage refused — a generation is running.');
      return null;
    }
    _isGenerating = true;
    _statusMessage = 'Generating image...';
    _lastGeneratedImage = null;
    _lastSavedPath = null;
    _genProgress = null;
    _genPreview = null;
    _notify();

    // Callers that don't specify a negative prompt (guest portraits, the
    // character creators, web chargen) get the user's configured default —
    // previously those paths silently generated with none. An explicit ''
    // still means "no negative". Remote APIs ignore negatives (see the
    // remote generators below).
    negativePrompt ??= _storage.imageGenSettings.imageGenNegativePrompt;

    // Portrait requests (character/persona portraits, guest card art) orient
    // the configured size vertically when the caller didn't pass an explicit
    // size. Previously this flag was accepted but ignored, so portraits came
    // out landscape whenever the default size was landscape.
    if (size == null && isPortrait) {
      final (w, h) = _parseSize(_storage.imageGenSettings.imageGenSize);
      if (w > h) size = '${h}x$w';
    }

    try {
      Uint8List imageBytes;

      final backend = ImageGenBackend.fromKey(
        _storage.imageGenSettings.imageGenBackend,
      );

      // Resolve what the reference image MEANS for this backend + model (the
      // single seam). Create keeps today's behavior; Edit routes an edit model
      // to editConditioning, and refuses honestly when the backend can't edit.
      //
      // Model-slot split (phase #12): EDIT intent resolves against the edit
      // slot, create against the create slot. One shared slot used to let an
      // edit model left selected after an Edit session silently poison base
      // generation (edit models can't txt2img). An explicit [model] wins
      // (batch flows pass their own). ComfyUI's edit path ignores this — its
      // models come from the comfyEdit* workflow slots.
      final refModelName =
          model ??
          (intent == StudioIntent.edit
              ? _storage.imageGenSettings.imageGenEditModel
              : _storage.imageGenSettings.imageGenModel);
      final refCapability = ImageReferenceResolver.resolveForBackend(
        backend: backend,
        modelName: refModelName,
      );
      final refCount = (referenceImage != null && referenceImage.isNotEmpty)
          ? 1
          : 0;
      final refRole = routeReference(
        intent: intent,
        attachedRefCount: refCount,
        cap: refCapability,
      );
      if (refRole == ImageReferenceRole.unsupported) {
        _statusMessage =
            refCapability.degradeReason ??
            'This backend can’t edit from a photo. Try Create instead.';
        _isGenerating = false;
        _notify();
        return null;
      }

      if (backend == ImageGenBackend.a1111 ||
          backend == ImageGenBackend.drawThings) {
        final isDrawThings =
            _storage.imageGenSettings.imageGenBackend == 'drawthings';

        if (isDrawThings) {
          // Use gRPC for Draw Things (Python client bridge)
          _statusMessage = 'Connecting to Draw Things...';
          _notify();

          // Slot-resolved above (edit intent → edit slot).
          final modelCheckpoint = refModelName;
          // Relaxed .ckpt check: gRPC file list returns the actual filenames Draw Things knows about
          // (may be .ckpt, .safetensors, or bare names). Empty is allowed (uses current in DT).
          if (modelCheckpoint.isNotEmpty &&
              !modelCheckpoint.toLowerCase().contains('.')) {
            // Only warn on clearly bad names; let the CLI/DT surface the real error
          }

          try {
            final grpcService = _ensureDrawThingsGrpc;
            final imageSize = size ?? _storage.imageGenSettings.imageGenSize;
            final (width, height) = _parseSize(imageSize);
            final steps = _storage.imageGenSettings.imageGenSteps;
            final cfgScale = _storage.imageGenSettings.imageGenCfgScale;
            final effectiveSeed =
                seed ?? _storage.imageGenSettings.imageGenSeed;

            // DT-native advanced knobs (shared sliders still used for steps/cfg/seed/size)
            final sampler = _storage.imageGenSettings.drawThingsSampler;
            final shift = _storage.imageGenSettings.drawThingsShift;
            // Unified img2img denoise. Draw Things only consults this when a
            // reference image is present (pure txt2img ignores it), so it is
            // always safe to pass. Replaces the retired drawThingsStrength knob.
            final strength =
                denoise ?? _storage.imageGenSettings.imageGenDenoise;
            final seedMode = _storage.drawThingsSeedMode;
            final teaCache = _storage.drawThingsTeaCache;
            final cfgZeroStar = _storage.drawThingsCfgZeroStar;
            // Same shared LoRA setting the A1111 path uses; DT applies it
            // natively via the generation config instead of a prompt tag.
            final loraName = _storage.imageGenSettings.imageGenLora;
            final loraWeight = _storage.imageGenSettings.imageGenLoraWeight;

            // Edit models (Qwen-Image-Edit / Flux Kontext) read the reference as
            // conditioning. The Edit tab keeps its OWN edit-scoped copy of these
            // knobs (steps/CFG/sampler/shift/seed-mode) so tuning an edit never
            // clobbers Create's txt2img settings — see edit_profile.dart. This
            // service is a DUMB PIPE for them: whatever the user set on the Edit
            // tab is sent verbatim, no silent override.
            var dtStrength = strength;
            var dtSteps = steps;
            var dtCfg = cfgScale;
            var dtShift = shift;
            var dtSampler = sampler;
            var dtSeedMode = seedMode;
            var dtLoras = loraName.isEmpty
                ? const <Map<String, dynamic>>[]
                : [
                    {'file': loraName, 'weight': loraWeight},
                  ];
            if (refRole == ImageReferenceRole.editConditioning) {
              // Every knob the user sees on the Edit tab, honored as-is (the
              // edit-scoped store is seeded with the field-tested recipe so the
              // FIRST edit already works — UniPC + moderate CFG — without
              // clobbering Create). The "how much should change" slider provides
              // the denoise strength; the user's LoRA rides along unchanged.
              dtSteps = _storage.editSteps;
              dtCfg = _storage.editCfgScale;
              dtSampler = _storage.editSampler;
              dtShift = _storage.editShift;
              dtSeedMode = _storage.editSeedMode;
              dtStrength = editStrength ?? kEditRecommendedStrength;
              _statusMessage = refCapability.editKind == EditModelKind.kontext
                  ? 'Editing with Flux Kontext...'
                  : 'Editing with Qwen-Image-Edit...';
              _notify();
            }

            imageBytes = await _generateViaDrawThingsGrpc(
              grpcService: grpcService,
              prompt: prompt,
              negativePrompt: negativePrompt,
              model: modelCheckpoint,
              width: width,
              height: height,
              steps: dtSteps,
              cfgScale: dtCfg,
              seed: effectiveSeed,
              strength: dtStrength,
              shift: dtShift,
              sampler: dtSampler,
              seedMode: dtSeedMode,
              teaCache: teaCache,
              cfgZeroStar: cfgZeroStar,
              loras: dtLoras,
              referenceImage: referenceImage,
              onProgress: (step, total) => _updateGenProgress(
                total > 0 ? (step / total).clamp(0.0, 1.0) : null,
              ),
            );
          } catch (e) {
            // A "Generation error from CLI: …" means the gRPC server WAS reached
            // and the generation itself failed (bad LoRA, incompatible model,
            // etc.) — the old code hid that behind a misleading "check the gRPC
            // server" message, which made LoRA/edit failures undiagnosable.
            // Surface the real Draw Things reason (first line, path/length
            // trimmed); keep the connection hint only for actual connect errors.
            final msg = e.toString();
            const genMarker = 'Generation error from CLI: ';
            final idx = msg.indexOf(genMarker);
            String safe;
            if (idx >= 0) {
              var detail = msg.substring(idx + genMarker.length).trim();
              detail = detail.split('\n').first.trim();
              if (detail.isEmpty || detail == 'null') {
                detail = 'the backend rejected the request '
                    '(often an incompatible LoRA or model for editing).';
              }
              if (detail.length > 240) detail = '${detail.substring(0, 240)}…';
              safe = 'Draw Things couldn’t generate: $detail';
            } else if (msg.contains('libfpzip')) {
              // The fpzip pre-flight fires BEFORE any socket is opened, so
              // the connection hint below would send the user off checking a
              // host/port that just tested green. Draw Things returns its
              // pictures as fpzip-compressed tensors and only the macOS build
              // carries that decoder.
              safe = Platform.isMacOS
                  ? 'Draw Things pictures can’t be unpacked — this copy of '
                        'Front Porch AI is missing its image decoder. '
                        'Reinstalling usually fixes it; until then, pick '
                        'another image backend.'
                  : 'Draw Things pictures can only be unpacked on macOS. '
                        'Front Porch AI on ${Platform.operatingSystem} can '
                        'talk to Draw Things but can’t turn its output into '
                        'an image — use ComfyUI or Automatic1111 instead.';
            } else if (msg.contains('CLI returned no parseable') ||
                msg.contains('connect') ||
                msg.contains('gRPC') ||
                msg.contains('timed out')) {
              safe =
                  'Draw Things generation failed. Check that the gRPC server is enabled in Draw Things and the host/port are correct.';
            } else {
              safe = 'Draw Things connection or generation failed.';
            }
            _statusMessage = safe;
            debugPrint('ImageGen: Draw Things error: $e');
            _isGenerating = false;
            _notify();
            return null;
          }
        } else {
          // Use HTTP for A1111
          final localUrl = _storage.imageGenSettings.localImageGenUrl;
          if (localUrl.isEmpty) {
            _statusMessage = 'No local server URL configured.';
            _isGenerating = false;
            _notify();
            return null;
          }
          final imageSize = size ?? _storage.imageGenSettings.imageGenSize;
          final modelCheckpoint = refModelName;
          imageBytes = await _generateViaA1111(
            baseUrl: localUrl,
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: imageSize,
            modelCheckpoint: modelCheckpoint,
            switchModelFirst: modelCheckpoint.isNotEmpty,
            loraName: _storage.imageGenSettings.imageGenLora,
            loraWeight: _storage.imageGenSettings.imageGenLoraWeight,
            steps: _storage.imageGenSettings.imageGenSteps,
            cfgScale: _storage.imageGenSettings.imageGenCfgScale,
            samplerName: _storage.imageGenSettings.imageGenSampler,
            scheduler: _storage.imageGenSettings.imageGenScheduler,
            seed: seed ?? _storage.imageGenSettings.imageGenSeed,
            referenceImage: referenceImage,
            denoise: denoise ?? _storage.imageGenSettings.imageGenDenoise,
          );
        }
      } else if (backend == ImageGenBackend.comfyUi) {
        // ── ComfyUI (HTTP + bundled txt2img workflow) ──────────────────
        _statusMessage = 'Connecting to ComfyUI...';
        _notify();
        try {
          final comfy = _ensureComfyUi;
          final (width, height) = _parseSize(
            size ?? _storage.imageGenSettings.imageGenSize,
          );
          // The stored sampler is shared across backends and may be an
          // A1111-style name; normalize it against what this server offers.
          final available = await comfy.fetchSamplers();
          final storedSampler = _storage.imageGenSettings.imageGenSampler;
          // An explicit user scheduler wins; 'Automatic' derives it from the
          // sampler (Karras-flavored names → karras, else normal) exactly as
          // before, so the default path is unchanged.
          final storedScheduler = _storage.imageGenSettings.imageGenScheduler;
          final scheduler = (storedScheduler.isNotEmpty &&
                  storedScheduler != 'Automatic')
              ? storedScheduler
              : ComfyUiService.schedulerFor(storedSampler);
          if (refRole == ImageReferenceRole.editConditioning &&
              referenceImage != null) {
            // ComfyUI instruction-edit: run the SELECTED workflow (a bundled
            // preset or the user's uploaded graph) via the token engine. The
            // edit-scoped knobs supply steps/CFG/strength(→denoise)/shift; the
            // sampler/scheduler use ComfyUI-friendly defaults (the DT sampler
            // int doesn't map cleanly). Model slots come from the user's picks.
            _statusMessage = 'Editing with ComfyUI...';
            _notify();
            final storedSeed = seed ?? _storage.imageGenSettings.imageGenSeed;
            final req = resolveComfyEditRequest(
              workflowId: _storage.comfyEditWorkflowId,
              uploadedWorkflowJson: _storage.comfyEditUploadedWorkflow,
              modelChoices: _storage.comfyEditModelChoices,
              prompt: prompt,
              negative: negativePrompt,
              seed: storedSeed == -1 ? Random().nextInt(1 << 31) : storedSeed,
              steps: _storage.editSteps,
              cfg: _storage.editCfgScale,
              denoise: editStrength ?? kEditRecommendedStrength,
              shift: _storage.editShift,
            );
            if (req == null) {
              throw Exception(
                'No ComfyUI edit workflow is set up. Pick a preset (and its '
                'models) or upload a workflow in the Edit tab.',
              );
            }
            imageBytes = await comfy.generateImageEdit(
              referenceImageBytes: referenceImage,
              workflowTemplate: req.template,
              tokenValues: req.values,
              onProgress: _updateGenProgress,
            );
          } else {
            imageBytes = await comfy.generateImage(
              prompt: prompt,
              negativePrompt: negativePrompt,
              model: refModelName,
              width: width,
              height: height,
              steps: _storage.imageGenSettings.imageGenSteps,
              cfgScale: _storage.imageGenSettings.imageGenCfgScale,
              seed: seed ?? _storage.imageGenSettings.imageGenSeed,
              samplerName: ComfyUiService.normalizeSampler(
                storedSampler,
                available,
              ),
              scheduler: scheduler,
              loraName: _storage.imageGenSettings.imageGenLora,
              loraWeight: _storage.imageGenSettings.imageGenLoraWeight,
              referenceImageBytes: referenceImage,
              denoise: denoise ?? _storage.imageGenSettings.imageGenDenoise,
              onProgress: _updateGenProgress,
            );
          }
        } catch (e) {
          // Sanitize for user display (mirrors the Draw Things branch).
          final msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
          _statusMessage = msg.startsWith('ComfyUI') || msg.contains('model')
              ? msg
              : 'ComfyUI generation failed. Check that ComfyUI is running and '
                    'the URL is correct.';
          debugPrint('ImageGen: ComfyUI error: $e');
          _isGenerating = false;
          _notify();
          return null;
        }
      } else {
        // ── Remote API ─────────────────────────────────────────────────
        if (_storage.backendSettings.remoteApiKey.isEmpty) {
          _statusMessage = 'No API key configured.';
          _isGenerating = false;
          _notify();
          return null;
        }

        final imageModel = refModelName;
        if (imageModel.isEmpty) {
          _statusMessage = 'No image model selected.';
          _isGenerating = false;
          _notify();
          return null;
        }

        final imageSize = size ?? _storage.imageGenSettings.imageGenSize;
        final apiUrl = _storage.backendSettings.remoteApiUrl;
        final apiKey = _storage.backendSettings.remoteApiKeyFor(apiUrl);

        // Remote EDIT when an edit model + a reference are in play: the
        // instruction (`prompt`) + the reference image go to the provider's edit
        // shape (OpenAI-compatible /images/edits, or OpenRouter's multimodal
        // chat). Otherwise the existing txt2img path, untouched.
        final remoteEdit =
            refRole == ImageReferenceRole.editConditioning &&
            referenceImage != null;
        if (remoteEdit) {
          _statusMessage = 'Editing with $imageModel...';
          _notify();
        }
        if (_isOpenRouterStyle(apiUrl)) {
          imageBytes = await _generateViaOpenRouter(
            apiUrl: apiUrl,
            apiKey: apiKey,
            model: imageModel,
            prompt: prompt,
            size: imageSize,
            editImage: remoteEdit ? referenceImage : null,
          );
        } else {
          imageBytes = await _generateViaOpenAICompat(
            apiUrl: apiUrl,
            apiKey: apiKey,
            model: imageModel,
            prompt: prompt,
            negativePrompt: negativePrompt,
            size: imageSize,
            editImage: remoteEdit ? referenceImage : null,
          );
        }
      }

      _lastGeneratedImage = imageBytes;
      _statusMessage = 'Image generated successfully.';
      debugPrint('ImageGen: Returning ${imageBytes.length} bytes');
      _notify();
      return imageBytes;
    } catch (e) {
      _statusMessage = 'Generation failed: $e';
      _notify();
      return null;
    } finally {
      _isGenerating = false;
      _genProgress = null;
      _genPreview = null;
      _notify();
    }
  }
}
