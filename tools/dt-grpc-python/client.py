"""
Draw Things gRPC Client — FlatBuffer + TLS

Drives Draw Things image/video generation programmatically via gRPC.
Handles FlatBuffer-encoded GenerationConfiguration and content-addressable images.

Usage:
    from draw_things_client.client import DrawThingsClient

    client = DrawThingsClient("localhost", 7859)
    result = client.generate_image(
        image_path="~/Downloads/photo.jpg",
        prompt="woman standing up, same person same face",
        config=QwenImageEditConfig(strength=0.8)
    )
    result.save("output.png")
"""

import grpc
import hashlib
import os
import struct
import sys
import time
import zlib
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional

import numpy as np
import fpzip
from PIL import Image
import flatbuffers

# Add parent dir so FlatBuffer-generated modules are importable
sys.path.insert(0, os.path.dirname(__file__))

import GenerationConfiguration as GenConfig
import LoRA as LoRAFB
import LoRAMode as LoRAModeFB
import SamplerType as SamplerTypeFB
import SeedMode as SeedModeFB

import imageService_pb2 as pb2
import imageService_pb2_grpc as pb2_grpc


# ─── Enums ────────────────────────────────────────────────────────────────────

class Sampler:
    DPMPP2M_KARRAS = 0
    EULER_A = 1
    DDIM = 2
    PLMS = 3
    DPMPP_SDE_KARRAS = 4
    UNIPC = 5
    LCM = 6
    EULER_A_SUBSTEP = 7
    DPMPP_SDE_SUBSTEP = 8
    TCD = 9
    EULER_A_TRAILING = 10
    DPMPP_SDE_TRAILING = 11
    DPMPP2M_AYS = 12
    EULER_A_AYS = 13
    DPMPP_SDE_AYS = 14
    DPMPP2M_TRAILING = 15
    DDIM_TRAILING = 16
    UNIPC_TRAILING = 17
    UNIPC_AYS = 18

class SeedMode:
    LEGACY = 0
    TORCH_CPU = 1
    SCALE_ALIKE = 2
    NVIDIA_GPU = 3

class LoRAMode:
    ALL = 0
    BASE = 1
    REFINER = 2


# ─── Model Constants ──────────────────────────────────────────────────────────

# Models available on your machine
QWEN_IMAGE = "qwen_image_1.0_q6p.ckpt"
QWEN_IMAGE_LIGHTNING_4 = "qwen_image_1.0_lightning_4_step_v2.0_lora_f16.ckpt"
QWEN_IMAGE_LIGHTNING_8 = "qwen_image_1.0_lightning_8_step_v2.0_lora_f16.ckpt"
QWEN_IMAGE_VAE = "qwen_image_vae_f16.ckpt"

WAN_HNE_I2V = "wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt"
WAN_LNE_I2V = "wan_v2.2_a14b_lne_i2v_q6p_svd.ckpt"
WAN_HNE_LIGHTNING = "wan_v2.2_a14b_hne_i2v_lightning_v1.0_lora_f16.ckpt"
WAN_LNE_LIGHTNING = "wan_v2.2_a14b_lne_i2v_lightning_v1.0_lora_f16.ckpt"

WAN_5B_TI2V = "wan_v2.2_5b_ti2v_q8p.ckpt"
WAN_VACE_1_3B = "wan_v2.1_1.3b_vace_480p_f16.ckpt"

RESTOREFORMER = "restoreformer_v1.0_f16.ckpt"


# ─── NNC Tensor Encoding ────────────────────────────────────────────────────
# Format: [uint32 identifier][ccv_nnc_tensor_param_t (64 bytes)][data]
# ccv_nnc_tensor_param_t = { int type, int format, int datatype, int reserved, int dim[12] }

CCV_TENSOR_CPU_MEMORY = 0x1
CCV_TENSOR_FORMAT_NHWC = 0x02
CCV_16F = 0x20000  # float16
CCV_32F = 0x04000  # float32
CCV_NNC_MAX_DIM_ALLOC = 12


def image_to_nnc_tensor(image_path: str, target_width: int = None, target_height: int = None) -> bytes:
    """
    Convert an image file to NNC tensor binary format (uncompressed).

    Matches Draw Things ImageConverter.tensor(from:):
    - Shape: NHWC(1, H, W, 3)
    - Dtype: float16
    - Normalization: pixel * 2 / 255 - 1  →  [-1, 1]
    - identifier=0 → raw uncompressed data
    """
    img = Image.open(image_path).convert("RGB")

    # Resize if target dimensions specified
    if target_width and target_height:
        img = img.resize((target_width, target_height), Image.LANCZOS)

    w, h = img.size
    pixels = np.array(img, dtype=np.float32)  # (H, W, 3) uint8 → float32

    # Normalize to [-1, 1] matching Draw Things: value * 2 / 255 - 1
    pixels = pixels * 2.0 / 255.0 - 1.0

    # Convert to float16
    pixels_f16 = pixels.astype(np.float16)

    # Build NNC tensor binary format
    # identifier=0 → uncompressed raw data (no codec needed)
    identifier = struct.pack("<I", 0)

    dims = [0] * CCV_NNC_MAX_DIM_ALLOC
    dims[0] = 1  # N
    dims[1] = h  # H
    dims[2] = w  # W
    dims[3] = 3  # C

    params = struct.pack(
        "<" + "i" * (4 + CCV_NNC_MAX_DIM_ALLOC),
        CCV_TENSOR_CPU_MEMORY,   # type
        CCV_TENSOR_FORMAT_NHWC,  # format
        CCV_16F,                 # datatype (float16)
        0,                       # reserved
        *dims                    # dim[12]
    )

    # Raw float16 bytes
    raw_data = pixels_f16.tobytes()

    return identifier + params + raw_data


def nnc_tensor_to_image(tensor_data: bytes, output_path: str) -> Image.Image:
    """Decode an NNC tensor (from gRPC response) back to a PIL Image."""
    compressed = tensor_data[68:]  # Skip 4-byte identifier + 64-byte params
    tensor = fpzip.decompress(compressed)  # Returns (1, H, W, 3) float32
    pixels = (tensor[0] + 1.0) * 255.0 / 2.0
    pixels = np.clip(pixels, 0, 255).astype(np.uint8)
    img = Image.fromarray(pixels)
    if output_path:
        img.save(output_path)
    return img


# ─── Config Dataclasses ──────────────────────────────────────────────────────

@dataclass
class LoRAConfig:
    file: str
    weight: float = 1.0
    mode: int = LoRAMode.ALL  # 0=All, 1=Base, 2=Refiner


@dataclass
class GenerationConfig:
    """Base generation config — maps to FlatBuffer GenerationConfiguration."""
    model: str = ""
    refiner_model: str = ""
    start_width: int = 512
    start_height: int = 512
    seed: int = 0  # 0 = random
    steps: int = 4
    guidance_scale: float = 1.0
    strength: float = 1.0
    shift: float = 1.0
    sampler: int = Sampler.DDIM_TRAILING
    seed_mode: int = SeedMode.SCALE_ALIKE
    num_frames: int = 0
    batch_count: int = 1
    batch_size: int = 1
    refiner_start: float = 0.7
    preserve_original_after_inpaint: bool = True
    # TeaCache
    tea_cache: bool = False
    tea_cache_threshold: float = 0.15
    tea_cache_start: int = 2
    tea_cache_end: int = -1
    tea_cache_max_skip_steps: int = 3
    # Causal Inference
    causal_inference_enabled: bool = False
    causal_inference: int = 3
    causal_inference_pad: int = 0
    # Face restoration
    face_restoration: str = ""
    # LoRAs
    loras: list = field(default_factory=list)
    # CFG
    cfg_zero_star: bool = False
    # Additional fields needed for exact config match
    resolution_dependent_shift: bool = False  # User has this false
    mask_blur: float = 1.5
    sharpness: float = 0.0


def qwen_image_edit_config(strength=0.8, steps=4, lightning=True) -> GenerationConfig:
    """Pre-configured for Qwen Image character editing — user's exact config."""
    loras = []
    if lightning and steps <= 4:
        loras.append(LoRAConfig(file=QWEN_IMAGE_LIGHTNING_4, weight=1.0))
    elif lightning and steps <= 8:
        loras.append(LoRAConfig(file=QWEN_IMAGE_LIGHTNING_8, weight=1.0))

    # NOTE: start_width/start_height are pixel_size / 64
    return GenerationConfig(
        model=QWEN_IMAGE,
        refiner_model=QWEN_IMAGE,  # User has refiner = same model
        start_width=512 // 64,   # 512px → 8 in FlatBuffer
        start_height=1024 // 64, # 1024px → 16 in FlatBuffer
        steps=steps,
        guidance_scale=1.0 if lightning else 3.5,
        strength=strength,
        shift=3.0,  # User's exact shift value
        sampler=Sampler.UNIPC_TRAILING,  # User's sampler=17
        seed_mode=SeedMode.SCALE_ALIKE,
        refiner_start=0.1,  # User's refiner_start
        resolution_dependent_shift=False,  # User has this false
        loras=loras,
    )


def wan_i2v_lightning_config(
    width=832, height=448, num_frames=33,
    causal_inference=17, causal_inference_pad=5
) -> GenerationConfig:
    """Pre-configured for Wan 2.2 I2V Lightning 4-step (your working config)."""
    # NOTE: start_width/start_height are pixel_size / 64 in FlatBuffer
    return GenerationConfig(
        model=WAN_HNE_I2V,
        refiner_model=WAN_LNE_I2V,
        start_width=width // 64,   # 832px → 13
        start_height=height // 64, # 448px → 7
        steps=4,
        guidance_scale=1.0,
        strength=1.0,
        shift=3.0,
        sampler=Sampler.DDIM_TRAILING,
        seed_mode=SeedMode.SCALE_ALIKE,
        num_frames=num_frames,
        refiner_start=0.1,
        preserve_original_after_inpaint=True,
        causal_inference_enabled=causal_inference > 0,
        causal_inference=causal_inference,
        causal_inference_pad=causal_inference_pad,
        loras=[
            LoRAConfig(file=WAN_HNE_LIGHTNING, weight=0.9, mode=LoRAMode.BASE),
            LoRAConfig(file=WAN_LNE_LIGHTNING, weight=0.8, mode=LoRAMode.REFINER),
        ],
    )


# ─── FlatBuffer Builder ──────────────────────────────────────────────────────

def build_config_flatbuffer(config: GenerationConfig) -> bytes:
    """Serialize GenerationConfig to FlatBuffer bytes."""
    builder = flatbuffers.Builder(1024)

    # Pre-create strings and tables (must be done before starting the main table)
    model_offset = builder.CreateString(config.model) if config.model else None
    refiner_offset = builder.CreateString(config.refiner_model) if config.refiner_model else None
    face_offset = builder.CreateString(config.face_restoration) if config.face_restoration else None

    # Build LoRA tables
    lora_offsets = []
    for lora in config.loras:
        lora_file = builder.CreateString(lora.file)
        LoRAFB.LoRAStart(builder)
        LoRAFB.LoRAAddFile(builder, lora_file)
        LoRAFB.LoRAAddWeight(builder, lora.weight)
        LoRAFB.LoRAAddMode(builder, lora.mode)
        lora_offsets.append(LoRAFB.LoRAEnd(builder))

    # Build LoRA vector
    loras_vector = None
    if lora_offsets:
        GenConfig.GenerationConfigurationStartLorasVector(builder, len(lora_offsets))
        for lo in reversed(lora_offsets):
            builder.PrependUOffsetTRelative(lo)
        loras_vector = builder.EndVector()

    # Build main table
    GenConfig.GenerationConfigurationStart(builder)
    GenConfig.GenerationConfigurationAddStartWidth(builder, config.start_width)
    GenConfig.GenerationConfigurationAddStartHeight(builder, config.start_height)
    GenConfig.GenerationConfigurationAddSeed(builder, config.seed)
    GenConfig.GenerationConfigurationAddSteps(builder, config.steps)
    GenConfig.GenerationConfigurationAddGuidanceScale(builder, config.guidance_scale)
    GenConfig.GenerationConfigurationAddStrength(builder, config.strength)
    if model_offset:
        GenConfig.GenerationConfigurationAddModel(builder, model_offset)
    GenConfig.GenerationConfigurationAddSampler(builder, config.sampler)
    GenConfig.GenerationConfigurationAddBatchCount(builder, config.batch_count)
    GenConfig.GenerationConfigurationAddBatchSize(builder, config.batch_size)
    if refiner_offset:
        GenConfig.GenerationConfigurationAddRefinerModel(builder, refiner_offset)
    GenConfig.GenerationConfigurationAddRefinerStart(builder, config.refiner_start)
    GenConfig.GenerationConfigurationAddSeedMode(builder, config.seed_mode)
    if config.num_frames > 0:
        GenConfig.GenerationConfigurationAddNumFrames(builder, config.num_frames)
    GenConfig.GenerationConfigurationAddShift(builder, config.shift)
    GenConfig.GenerationConfigurationAddPreserveOriginalAfterInpaint(builder, config.preserve_original_after_inpaint)
    GenConfig.GenerationConfigurationAddResolutionDependentShift(builder, config.resolution_dependent_shift)
    GenConfig.GenerationConfigurationAddMaskBlur(builder, config.mask_blur)
    GenConfig.GenerationConfigurationAddSharpness(builder, config.sharpness)
    # TeaCache
    GenConfig.GenerationConfigurationAddTeaCache(builder, config.tea_cache)
    if config.tea_cache:
        GenConfig.GenerationConfigurationAddTeaCacheThreshold(builder, config.tea_cache_threshold)
        GenConfig.GenerationConfigurationAddTeaCacheStart(builder, config.tea_cache_start)
        GenConfig.GenerationConfigurationAddTeaCacheEnd(builder, config.tea_cache_end)
        GenConfig.GenerationConfigurationAddTeaCacheMaxSkipSteps(builder, config.tea_cache_max_skip_steps)
    # Causal Inference
    GenConfig.GenerationConfigurationAddCausalInferenceEnabled(builder, config.causal_inference_enabled)
    GenConfig.GenerationConfigurationAddCausalInference(builder, config.causal_inference)
    GenConfig.GenerationConfigurationAddCausalInferencePad(builder, config.causal_inference_pad)
    # Face restoration
    if face_offset:
        GenConfig.GenerationConfigurationAddFaceRestoration(builder, face_offset)
    # LoRAs
    if loras_vector:
        GenConfig.GenerationConfigurationAddLoras(builder, loras_vector)
    # CFG
    GenConfig.GenerationConfigurationAddCfgZeroStar(builder, config.cfg_zero_star)

    config_offset = GenConfig.GenerationConfigurationEnd(builder)
    builder.Finish(config_offset)

    return bytes(builder.Output())


# ─── gRPC Client ──────────────────────────────────────────────────────────────

@dataclass
class GenerationResult:
    """Result from a generation request."""
    images: list  # List of raw bytes (PNG/JPEG data)
    elapsed_seconds: float = 0.0
    signposts: list = field(default_factory=list)

    def save(self, path: str, index: int = 0):
        """Save the generated image to a file, decoding NNC tensor if needed."""
        if index < len(self.images):
            p = Path(path).expanduser()
            p.parent.mkdir(parents=True, exist_ok=True)
            data = self.images[index]

            # Check if it's an NNC tensor (not PNG/JPEG)
            if data[:4] != b'\x89PNG' and data[:2] != b'\xff\xd8':
                # NNC tensor → decode to PNG
                nnc_tensor_to_image(data, str(p))
                print(f"Saved: {p} (decoded from NNC tensor)")
            else:
                p.write_bytes(data)
                print(f"Saved: {p} ({len(data)} bytes)")
        else:
            print(f"No image at index {index} (got {len(self.images)} images)")

    def save_all(self, directory: str, prefix: str = "gen"):
        """Save all generated images to a directory."""
        d = Path(directory).expanduser()
        d.mkdir(parents=True, exist_ok=True)
        for i, img_data in enumerate(self.images):
            p = d / f"{prefix}_{i:03d}.png"
            if img_data[:4] != b'\x89PNG' and img_data[:2] != b'\xff\xd8':
                nnc_tensor_to_image(img_data, str(p))
            else:
                p.write_bytes(img_data)
            print(f"Saved: {p}")


class DrawThingsClient:
    """gRPC client for Draw Things with FlatBuffer config encoding."""

    def __init__(self, host: str = "localhost", port: int = 7859):
        self.host = host
        self.port = port
        self._channel = None
        self._stub = None

    def _connect(self):
        """Establish TLS connection (Draw Things uses self-signed cert)."""
        if self._channel is not None:
            return

        # Load Draw Things self-signed cert chain
        cert_path = Path(__file__).parent / "ca_chain.pem"
        if cert_path.exists():
            root_certs = cert_path.read_bytes()
        else:
            root_certs = None

        credentials = grpc.ssl_channel_credentials(
            root_certificates=root_certs,
        )
        options = [
            ('grpc.ssl_target_name_override', 'localhost'),
            ('grpc.max_receive_message_length', 500 * 1024 * 1024),  # 500MB for video
            ('grpc.max_send_message_length', 100 * 1024 * 1024),    # 100MB for images
        ]
        self._channel = grpc.secure_channel(
            f"{self.host}:{self.port}", credentials, options
        )
        self._stub = pb2_grpc.ImageGenerationServiceStub(self._channel)

    def echo(self, message: str = "hello") -> str:
        """Test connectivity."""
        self._connect()
        response = self._stub.Echo(pb2.EchoRequest(name=message))
        return response.message

    def files_exist(self, files: list) -> dict:
        """Check which model files exist on the server."""
        self._connect()
        response = self._stub.FilesExist(pb2.FileListRequest(files=files))
        return dict(zip(response.files, response.existences))

    def generate(
        self,
        config: GenerationConfig,
        prompt: str = "",
        negative_prompt: str = "",
        image_path: str = None,
        scale_factor: int = 1,
        verbose: bool = True,
    ) -> GenerationResult:
        """
        Submit a generation request and stream results.

        Args:
            config: GenerationConfig with all parameters
            prompt: Text prompt
            negative_prompt: Negative prompt
            image_path: Path to input image (for img2img/i2v)
            scale_factor: Image scale factor (1 for standard)
            verbose: Print progress signposts

        Returns:
            GenerationResult with output images
        """
        self._connect()

        # Build FlatBuffer config
        config_bytes = build_config_flatbuffer(config)

        # Build request
        request = pb2.ImageGenerationRequest(
            prompt=prompt,
            negativePrompt=negative_prompt,
            configuration=config_bytes,
            scaleFactor=scale_factor,
            user="claude-client",
        )

        # Add image if provided — encode as NNC tensor
        if image_path:
            img_path = Path(image_path).expanduser()
            if not img_path.exists():
                raise FileNotFoundError(f"Image not found: {img_path}")

            # Convert image to NNC tensor format (float16 NHWC, [-1,1])
            # Target resolution from config (start_width/height * 64)
            target_w = config.start_width * 64
            target_h = config.start_height * 64
            tensor_data = image_to_nnc_tensor(str(img_path), target_w, target_h)
            img_hash = hashlib.sha256(tensor_data).digest()

            request.image = img_hash
            request.contents.append(tensor_data)

            if verbose:
                print(f"Input image: {img_path} → tensor ({len(tensor_data)} bytes, {target_w}x{target_h})")

        if verbose:
            print(f"Model: {config.model}")
            print(f"Steps: {config.steps}, Guidance: {config.guidance_scale}")
            print(f"Resolution: {config.start_width}x{config.start_height} (latent)")
            if config.loras:
                for l in config.loras:
                    print(f"LoRA: {l.file} (w={l.weight})")
            print(f"Prompt: {prompt}")
            print("Generating...")

        # Stream response
        start_time = time.time()
        images = []
        signposts = []

        try:
            for response in self._stub.GenerateImage(request):
                # Check for signpost (progress indicator)
                if response.HasField('currentSignpost'):
                    sp = response.currentSignpost
                    signpost_type = sp.WhichOneof('signpost')
                    if signpost_type:
                        signposts.append(signpost_type)
                        if verbose:
                            if signpost_type == 'sampling':
                                print(f"  Step {sp.sampling.step}...")
                            elif signpost_type == 'textEncoded':
                                print("  Text encoded")
                            elif signpost_type == 'imageEncoded':
                                print("  Image encoded")
                            elif signpost_type == 'imageDecoded':
                                print("  Image decoded")
                            elif signpost_type == 'faceRestored':
                                print("  Face restored")

                # Collect generated images
                for img_data in response.generatedImages:
                    if img_data:
                        images.append(img_data)
        except grpc.RpcError as e:
            print(f"gRPC Error: {e.code()} — {e.details()}")
            raise

        elapsed = time.time() - start_time

        if verbose:
            print(f"Done in {elapsed:.1f}s — got {len(images)} image(s)")

        return GenerationResult(
            images=images,
            elapsed_seconds=elapsed,
            signposts=signposts,
        )

    def close(self):
        """Close the gRPC channel."""
        if self._channel:
            self._channel.close()
            self._channel = None
            self._stub = None

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


# ─── Pipeline Helpers ─────────────────────────────────────────────────────────

def edit_character_image(
    client: DrawThingsClient,
    image_path: str,
    prompt: str,
    output_path: str,
    strength: float = 0.8,
    steps: int = 4,
    negative_prompt: str = "different person, changed face, different features",
) -> GenerationResult:
    """
    Edit a character image while preserving identity using Qwen Image.

    Args:
        client: Connected DrawThingsClient
        image_path: Path to input character image
        prompt: What to change (e.g., "she stands up, same person same face")
        output_path: Where to save the result
        strength: Edit strength (0.7=subtle, 0.9=major)
        steps: Generation steps (4 with Lightning, 8 for quality)
    """
    config = qwen_image_edit_config(strength=strength, steps=steps)
    result = client.generate(
        config=config,
        prompt=prompt,
        negative_prompt=negative_prompt,
        image_path=image_path,
    )
    if result.images:
        result.save(output_path)
    return result


def generate_video_clip(
    client: DrawThingsClient,
    image_path: str,
    prompt: str,
    output_path: str,
    num_frames: int = 33,
    width: int = 832,
    height: int = 448,
) -> GenerationResult:
    """
    Generate I2V clip from a start frame using Wan Lightning 4-step.

    Args:
        client: Connected DrawThingsClient
        image_path: Path to start frame image
        prompt: Motion description (e.g., "woman stands up smoothly")
        output_path: Where to save the video/image
        num_frames: Number of frames (33=~2s, 49=~3s, 81=~5s)
    """
    config = wan_i2v_lightning_config(
        width=width, height=height, num_frames=num_frames
    )
    result = client.generate(
        config=config,
        prompt=prompt,
        image_path=image_path,
    )
    if result.images:
        result.save(output_path)
    return result


# ─── Main: Quick Test ─────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("=== Draw Things gRPC Client Test ===\n")

    with DrawThingsClient() as client:
        # Test connectivity
        try:
            msg = client.echo("claude-test")
            print(f"Echo: {msg}")
        except Exception as e:
            print(f"Echo failed: {e}")
            print("Is Draw Things running with gRPC server on port 7859?")
            sys.exit(1)

        # Check models
        models = [QWEN_IMAGE, WAN_HNE_I2V, WAN_LNE_I2V,
                  QWEN_IMAGE_LIGHTNING_4, WAN_HNE_LIGHTNING, WAN_LNE_LIGHTNING]
        existence = client.files_exist(models)
        print("\nModel availability:")
        for model, exists in existence.items():
            status = "OK" if exists else "MISSING"
            print(f"  [{status}] {model}")

        print("\nClient ready. Use generate() to submit jobs.")
