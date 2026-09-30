// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'image_facade.dart';

/// A request to the phone desk that is refused, with a stable [code] and
/// words for the person. Nothing has been changed when this is thrown.
class DeskRefused implements Exception {
  const DeskRefused(this.code, this.message, [this.status = 400]);

  final String code;
  final String message;
  final int status;

  @override
  String toString() => 'DeskRefused($code)';
}

/// The most a graph file, or a picture to edit, may weigh.
const int kMaxDeskGraphBytes = 8 * 1024 * 1024;
const int kMaxDeskPictureBytes = 12 * 1024 * 1024;

/// Whether a config write would store a ComfyUI graph the caller supplied.
/// A graph is what Comfy runs on this computer, so it is credential-grade.
bool imageConfigUploadsGraph(Map<String, dynamic> body) {
  for (final key in [
    'comfyCreateUploadedWorkflow',
    'comfyEditUploadedWorkflow',
  ]) {
    final value = body[key];
    if (value is String && value.trim().isNotEmpty) return true;
  }
  return false;
}

/// [raw] as a ComfyUI graph the desk may store: within the size limit and a
/// JSON object. Throws [DeskRefused] otherwise.
String checkedDeskGraph(String raw) {
  if (utf8.encode(raw).length > kMaxDeskGraphBytes) {
    throw const DeskRefused(
      'too_large',
      'That graph is too large to use.',
      413,
    );
  }
  final kept = pngWorkflowText({'prompt': raw});
  if (kept == null || workflowNodeCount(kept) == 0) {
    throw const DeskRefused('not_graph', 'That file isn’t a ComfyUI graph.');
  }
  return kept;
}

extension ImageStudioDesk on ImageFacade {
  ImageGenSettings get _s => _storage.imageGenSettings;

  Future<void> _setWorkflow(bool edit, String id) =>
      edit ? _s.setComfyEditWorkflowId(id) : _s.setComfyCreateWorkflowId(id);

  Future<void> _setChoice(bool edit, String id, String token, String file) =>
      edit
      ? _s.setComfyEditModelChoice(id, token, file)
      : _s.setComfyCreateModelChoice(id, token, file);

  /// The model files the graph on the desk loads, as the readiness rule read
  /// them. Empty when Comfy cannot be read.
  Future<List<ComfyModelSlot>> _deskSlots(bool edit) async {
    final report = await checkStudioReady(settings: _s, edit: edit);
    return report.readiness.slots;
  }

  /// Fills the graph's empty text-encoder and VAE slots from the installed
  /// files, as the desktop desk does. A slot that holds a file is left alone.
  Future<void> _fillSupport(bool edit) async {
    if (_s.imageGenBackend != 'comfyui') return;
    final id = edit ? _s.comfyEditWorkflowId : _s.comfyCreateWorkflowId;
    if (id.isEmpty || id == kComfyUploadedWorkflowId) return;
    final tokens = [
      for (final slot in await _deskSlots(edit))
        if (slot.token.contains('CLIP') || slot.token.contains('VAE'))
          slot.token,
    ];
    final primary = studioPrimaryFor(_s, edit: edit);
    if (tokens.isEmpty || primary.isEmpty) return;
    final cat = await _image.fetchComfyCatalog(_s.comfyUiUrl);
    final fills = supportAutofill(
      workflowId: id,
      primary: primary,
      choices: edit ? _s.comfyEditModelChoices : _s.comfyCreateModelChoices,
      clips: cat.textEncoders,
      vaes: cat.vaes,
      tokens: tokens,
    );
    for (final entry in fills.entries) {
      await _setChoice(edit, id, entry.key, entry.value);
    }
  }

  /// Picks the primary model, the way the desktop desk does. A saved,
  /// template or legacy Comfy graph keeps its graph and takes the file in its
  /// own slot. A bundled graph follows the file's family, except that a file
  /// of no known family stays on the graph it was chosen on.
  Future<void> pickModel({required bool edit, required String file}) async {
    final name = _cleanName(file);
    if (_s.imageGenBackend == 'remote') {
      await _s.setRemoteImageModelFor(_s.imageRemoteApiUrl, name, edit: edit);
      return;
    }
    if (_s.imageGenBackend != 'comfyui') {
      await (edit ? _s.setImageGenEditModel(name) : _s.setImageGenModel(name));
      return;
    }
    final current = edit ? _s.comfyEditWorkflowId : _s.comfyCreateWorkflowId;
    final keep = deskKeepsWorkflow(current);
    final family = ImageModelFamily.detectFromName(name);
    final id = keep || (family == ModelFamily.unknown && !isGgufFile(name))
        ? current
        : workflowForModel(edit: edit, file: name);
    if (id != current) await _setWorkflow(edit, id);
    final token = keep
        ? deskPrimaryToken(
            workflowId: id,
            file: name,
            slots: await _deskSlots(edit),
          )
        : deskComfyToken(workflowId: id, file: name);
    await _setChoice(edit, id, token, name);
    await _fillSupport(edit);
  }

  /// Chooses a graph. The file already on the desk moves along only to a
  /// bundled graph of its own family; a saved or template graph keeps the
  /// files it has and empty slots are filled.
  Future<void> pickGraph({required bool edit, required String id}) async {
    final graph = _cleanName(id);
    final uploaded = edit
        ? _s.comfyEditUploadedWorkflow
        : _s.comfyCreateUploadedWorkflow;
    final bundled = edit
        ? kComfyEditPresets.any((p) => p.id == graph)
        : kComfyCreatePresets.any((p) => p.id == graph);
    final known =
        bundled ||
        graph.startsWith('comfy:') ||
        (graph == kComfyUploadedWorkflowId && uploaded.trim().isNotEmpty);
    if (!known) {
      throw const DeskRefused(
        'unknown_graph',
        'That graph is not on the list.',
      );
    }
    final file = studioPrimaryFor(_s, edit: edit);
    final chosen = isGgufFile(file) && graph == 'sd'
        ? workflowForModel(edit: edit, file: file)
        : graph;
    await _setWorkflow(edit, chosen);
    if (file.isNotEmpty &&
        _s.imageGenBackend == 'comfyui' &&
        !deskKeepsWorkflow(chosen) &&
        workflowForModel(edit: edit, file: file) == chosen) {
      await _setChoice(
        edit,
        chosen,
        deskComfyToken(workflowId: chosen, file: file),
        file,
      );
    }
    await _fillSupport(edit);
  }

  /// Sets one text-encoder, VAE or other slot of the graph on the desk.
  Future<void> pickSupport({
    required bool edit,
    required String token,
    required String file,
  }) async {
    final slot = _cleanName(token);
    if (!RegExp(r'^%MODEL_[A-Z0-9_]+%$').hasMatch(slot)) {
      throw const DeskRefused('bad_slot', 'That is not a model slot.');
    }
    final id = edit ? _s.comfyEditWorkflowId : _s.comfyCreateWorkflowId;
    await _setChoice(edit, id, slot, _cleanName(file));
  }

  String _cleanName(String value) {
    final name = value.trim();
    if (name.isEmpty ||
        name.length > 300 ||
        name.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const DeskRefused('bad_request', 'That name is not usable.');
    }
    return name;
  }

  /// Stores a graph file the phone sent (`.json`, or a PNG Comfy saved).
  ///
  /// Nothing is stored when the file is not a graph, is too large, or is
  /// meant for the other mode and [useFor] does not say which mode to use it
  /// for. [edit] is the mode the desk is on. The answer says which mode the
  /// graph is for (`create`, `edit` or `unstated`) and whether it was stored.
  Future<Map<String, dynamic>> saveGraphFile({
    required List<int> bytes,
    required String name,
    required bool edit,
    String? useFor,
  }) async {
    if (bytes.length > kMaxDeskGraphBytes) {
      throw const DeskRefused(
        'too_large',
        'That file is too large to use.',
        413,
      );
    }
    final json = workflowJsonFromBytes(bytes);
    if (json == null || workflowNodeCount(json) == 0) {
      final png = bytes.length >= 4 && bytes[0] == 137 && bytes[1] == 80;
      throw DeskRefused(
        png ? 'no_graph_in_image' : 'not_graph',
        png
            ? 'That image has no ComfyUI workflow saved inside it.'
            : 'That file isn’t a ComfyUI graph.',
      );
    }
    final stance = deskGraphStance(json);
    if (useFor != null && useFor != 'create' && useFor != 'edit') {
      throw const DeskRefused('bad_request', 'Use it for Create or for Edit.');
    }
    final target =
        useFor ?? (stance == (edit ? 'edit' : 'create') ? stance : null);
    if (target == null) {
      return {
        'stored': false,
        'stance': stance,
        'nodes': workflowNodeCount(json),
      };
    }
    final forEdit = target == 'edit';
    final title = name.trim().isEmpty ? 'workflow' : name.trim();
    final shown = title.length > 120 ? title.substring(0, 120) : title;
    if (forEdit) {
      await _s.setComfyEditUploadedWorkflow(json, title: shown);
      await _s.setComfyEditWorkflowId(kComfyUploadedWorkflowId);
    } else {
      await _s.setComfyCreateUploadedWorkflow(json, title: shown);
      await _s.setComfyCreateWorkflowId(kComfyUploadedWorkflowId);
    }
    return {
      'stored': true,
      'stance': stance,
      'mode': target,
      'nodes': workflowNodeCount(json),
      'title': shown,
    };
  }

  /// The picture an Edit works on, or a Create varies: a picture this app
  /// saved (by file name) or one the phone sent (a data URL).
  Future<Uint8List?> _reference(Map<String, dynamic> f) async {
    final saved = f['referenceFilename']?.toString() ?? '';
    final sent = f['referenceImage']?.toString() ?? '';
    Uint8List? bytes;
    if (saved.isNotEmpty) {
      final file = savedImageFile(saved);
      if (file == null) {
        throw const DeskRefused('no_picture', 'That picture is gone.', 404);
      }
      if (file.lengthSync() > kMaxDeskPictureBytes) {
        throw const DeskRefused('too_large', 'That picture is too large.', 413);
      }
      bytes = await file.readAsBytes();
    } else if (sent.isNotEmpty) {
      final comma = sent.indexOf(',');
      final head = comma < 0 ? '' : sent.substring(0, comma);
      if (!head.startsWith('data:image/') || !head.endsWith(';base64')) {
        throw const DeskRefused('bad_picture', 'That is not a picture.');
      }
      if (sent.length - comma > kMaxDeskPictureBytes * 4 ~/ 3 + 8) {
        throw const DeskRefused('too_large', 'That picture is too large.', 413);
      }
      try {
        bytes = base64Decode(sent.substring(comma + 1));
      } on FormatException {
        throw const DeskRefused('bad_picture', 'That is not a picture.');
      }
    }
    if (bytes != null && !_looksLikeImage(bytes)) {
      throw const DeskRefused('bad_picture', 'That is not a picture.');
    }
    return bytes;
  }

  bool _looksLikeImage(List<int> b) {
    if (b.length < 12) return false;
    final png = b[0] == 137 && b[1] == 80 && b[2] == 78 && b[3] == 71;
    final jpeg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
    final webp = b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45;
    return png || jpeg || webp;
  }
}
