# Draw Things gRPC Python Client

Python client for [Draw Things](https://drawthings.ai) image/video generation via its gRPC server. Handles FlatBuffer config encoding, NNC tensor image format, and TLS.

## Features

- **txt2img / img2img** via Qwen Image, SDXL, Flux, etc.
- **I2V video generation** via Wan 2.2 Lightning (A14B)
- **NNC tensor codec** — encode/decode Draw Things' native tensor format (fpzip compressed)
- **FlatBuffer configs** — full GenerationConfiguration encoding matching Draw Things exactly
- **TLS** — handles Draw Things' self-signed certificates
- **Pre-built configs** — Qwen Image edit, Wan I2V Lightning ready to use

## Setup

```bash
pip install -r requirements.txt
```

Enable the gRPC server in Draw Things: Settings > Developer > gRPC Server (port 7859).

## Quick Start

```python
from client import DrawThingsClient, qwen_image_edit_config, wan_i2v_lightning_config

client = DrawThingsClient()

# Test connection
print(client.echo("hello"))

# txt2img
config = qwen_image_edit_config(strength=1.0)
result = client.generate(config=config, prompt="a woman in a yoga studio")
result.save("output.png")

# img2img (character edit)
config = qwen_image_edit_config(strength=0.85)
result = client.generate(
    config=config,
    prompt="she stands up, same person same face same features",
    negative_prompt="different person, changed face",
    image_path="reference.jpg",
)
result.save("edited.png")

# I2V video
config = wan_i2v_lightning_config(width=832, height=448, num_frames=33)
result = client.generate(
    config=config,
    prompt="woman stands up smoothly, cinematic",
    image_path="start_frame.png",
)
result.save_all("frames/")

client.close()
```

## Files

| File | Description |
|------|-------------|
| `client.py` | Main gRPC client with NNC tensor encoding, FlatBuffer config builder |
| `run_pipeline.py` | Character consistency pipeline (key frames + video) |
| `character_pipeline.js` | Draw Things native JS scripting version |
| `config.fbs` | FlatBuffer schema for GenerationConfiguration |
| `ca_chain.pem` | TLS certificate for Draw Things gRPC server |
| `docs/` | Config references, optimization guides, scripting API docs |

## Key Technical Details

- **start_width/start_height** in FlatBuffer = `pixel_size / 64` (not raw pixels)
- **NNC tensor format**: `[uint32 identifier][ccv_nnc_tensor_param_t 64 bytes][data]`
  - NHWC layout, float16, normalized to [-1, 1]
  - identifier=0: raw data, non-zero: fpzip compressed
- **Image data**: content-addressable (SHA256 hash in `image` field, data in `contents`)

## Hardware Tested

- M4 Pro 48GB, macOS 26.2
- Qwen Image 1.0 q6p: ~40s per edit (4 Lightning steps)
- Wan I2V A14B Lightning: ~7 min per 33-frame clip (4 steps)
