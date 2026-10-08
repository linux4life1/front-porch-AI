// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// What a City96 `loader.py` needs before Qwen-Image GGUF can run.
class City96LoaderPatch {
  final String source;
  final bool changed;

  /// False when the file is not City96's loader, or a fork this patch
  /// cannot recognize. The file is left untouched.
  final bool recognized;

  const City96LoaderPatch({
    required this.source,
    required this.changed,
    required this.recognized,
  });
}

/// Stock City96 accepts `qwen_image` in its arch list but still rejects a
/// Qwen-Image GGUF that omits `general.architecture`, and it attaches an
/// mmproj only for `qwen2vl`. The graph keeps `UnetLoaderGGUF` and
/// `CLIPLoaderGGUF`. This updates that loader in place.
City96LoaderPatch patchCity96Loader(String source) {
  final crlf = source.contains('\r\n');
  var text = source.replaceAll('\r\n', '\n');
  final archOk = text.contains('arch_str = "qwen_image"');
  final clipOk = text.contains('arch == "qwen3vl"');
  if (archOk && clipOk) {
    return City96LoaderPatch(source: source, changed: false, recognized: true);
  }
  var changed = false;
  if (!archOk) {
    if (!text.contains(_kArchNeedle)) {
      return City96LoaderPatch(
        source: source,
        changed: false,
        recognized: false,
      );
    }
    text = text.replaceFirst(_kArchNeedle, _kArchReplace);
    changed = true;
  }
  if (!clipOk) {
    if (!text.contains(_kClipNeedle) || !text.contains(_kClipDef)) {
      return City96LoaderPatch(
        source: source,
        changed: false,
        recognized: false,
      );
    }
    if (!text.contains('def _qwen3vl_vision(')) {
      text = text.replaceFirst(_kClipDef, _kVisionHelper);
    }
    text = text.replaceFirst(_kClipNeedle, _kClipReplace);
    changed = true;
  }
  if (crlf) text = text.replaceAll('\n', '\r\n');
  return City96LoaderPatch(source: text, changed: changed, recognized: true);
}

const _kArchNeedle = '''
        compat = "sd.cpp" if arch_str is None else arch_str
        # import here to avoid changes to convert.py breaking regular models
        from .tools.convert import detect_arch
        try:
            arch_str = detect_arch(set(val[0] for val in tensors)).arch
        except Exception as e:
            raise ValueError(f"This model is not currently supported - ({e})")
''';

const _kArchReplace = '''
        compat = "sd.cpp" if arch_str is None else arch_str
        names = {val[0] for val in tensors}
        # Qwen-Image GGUFs omit general.architecture. Comfy detects the
        # unet from the tensors once this arch string is accepted.
        if "img_in.weight" in names and any(
            name.startswith("time_text_embed.timestep_embedder.") for name in names
        ):
            arch_str = "qwen_image"
        else:
            # import here to avoid changes to convert.py breaking regular models
            from .tools.convert import detect_arch
            try:
                arch_str = detect_arch(names).arch
            except Exception as e:
                raise ValueError(f"This model is not currently supported - ({e})")
''';

const _kClipNeedle = '''
        if arch == "qwen2vl":
            vsd = gguf_mmproj_loader(path)
            sd.update(vsd)
''';

const _kClipReplace = '''
        if arch == "qwen2vl":
            vsd = gguf_mmproj_loader(path)
            sd.update(vsd)
        elif arch == "qwen3vl":
            vsd = gguf_mmproj_loader(path)
            if not vsd:
                raise RuntimeError(
                    "Qwen3-VL text encoder needs its mmproj file in the same folder."
                )
            sd.update(_qwen3vl_vision(vsd))
''';

const _kClipDef = 'def gguf_clip_loader(path):';

const _kVisionHelper = '''
def _qwen3vl_vision(vsd):
    # gguf_mmproj_loader uses Qwen2-VL names. Comfy detects Qwen3-VL only
    # when model.visual.deepstack_merger_list.0.norm.weight is present.
    layers = sorted(
        {int(k.split(".")[2]) for k in vsd if k.startswith("v.deepstack.")}
    )
    out = {}
    for key, value in vsd.items():
        if key.startswith("v.deepstack."):
            _, _, layer, rest = key.split(".", 3)
            key = f"visual.deepstack_merger_list.{layers.index(int(layer))}.{rest}"
        key = key.replace("v.position_embd.", "visual.pos_embed.")
        key = key.replace(".attn_qkv.", ".attn.qkv.")
        key = key.replace(".mlp.up_proj.", ".mlp.linear_fc1.")
        key = key.replace(".mlp.down_proj.", ".mlp.linear_fc2.")
        key = key.replace(".fc1.", ".linear_fc1.")
        key = key.replace(".fc2.", ".linear_fc2.")
        key = key.replace("visual.merger.ln_q.", "visual.merger.norm.")
        key = key.replace("visual.merger.mlp.0.", "visual.merger.linear_fc1.")
        key = key.replace("visual.merger.mlp.2.", "visual.merger.linear_fc2.")
        out["model." + key] = value
    return out

def gguf_clip_loader(path):
''';
