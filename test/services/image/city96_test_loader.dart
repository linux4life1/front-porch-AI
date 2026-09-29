// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The parts of City96's stock `ComfyUI-GGUF/loader.py` the patch edits. Tests
/// write this into a temp folder; no test reads or writes a real install.
const String kStockCity96Loader = '''
def gguf_sd_loader(path, handle_prefix="model.diffusion_model.", is_text_model=False):
        compat = "sd.cpp" if arch_str is None else arch_str
        # import here to avoid changes to convert.py breaking regular models
        from .tools.convert import detect_arch
        try:
            arch_str = detect_arch(set(val[0] for val in tensors)).arch
        except Exception as e:
            raise ValueError(f"This model is not currently supported - ({e})")
    elif arch_str not in TXT_ARCH_LIST and is_text_model:
        pass

def gguf_clip_loader(path):
        if arch == "qwen2vl":
            vsd = gguf_mmproj_loader(path)
            sd.update(vsd)
    else:
        pass
    return sd
''';
