"""
Character Consistency Pipeline — Driven via gRPC

Phase 1: Generate character-consistent key frames using Qwen Image
Phase 2: Generate I2V transitions using Wan Lightning

Uses the user's exact working configs.
"""

import sys
import os
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))

from client import (
    DrawThingsClient, GenerationConfig, LoRAConfig,
    GenerationResult, Sampler, SeedMode, LoRAMode,
    QWEN_IMAGE, QWEN_IMAGE_LIGHTNING_4,
    WAN_HNE_I2V, WAN_LNE_I2V, WAN_HNE_LIGHTNING, WAN_LNE_LIGHTNING,
    build_config_flatbuffer,
)

# ─── Reference Image ──────────────────────────────────────────────────────────
REF_IMAGE = os.path.expanduser("~/Downloads/photo_5794272574841146840_y.jpg")
OUTPUT_DIR = os.path.expanduser("~/Pictures/CharacterPipeline")

# ─── Phase 1: Qwen Image Edit Config (User's exact working config) ───────────
def make_qwen_config(strength=1.0):
    """User's exact Qwen Image config from Draw Things."""
    # NOTE: start_width/start_height are pixel_size / 64 in FlatBuffer
    return GenerationConfig(
        model=QWEN_IMAGE,
        refiner_model=QWEN_IMAGE,  # User has refiner = same model
        start_width=512 // 64,    # 512px → 8
        start_height=1024 // 64,  # 1024px → 16
        seed=0,  # 0 = random
        steps=4,
        guidance_scale=1.0,
        strength=strength,
        shift=3.0,
        sampler=17,  # UniPCTrailing (user's sampler=17)
        seed_mode=SeedMode.SCALE_ALIKE,  # 2
        batch_count=1,
        batch_size=1,
        refiner_start=0.1,
        preserve_original_after_inpaint=True,
        cfg_zero_star=False,
        causal_inference_enabled=False,
        causal_inference_pad=0,
        loras=[
            LoRAConfig(
                file=QWEN_IMAGE_LIGHTNING_4,
                weight=1.0,
                mode=LoRAMode.ALL,
            ),
        ],
    )

# ─── Phase 2: Wan I2V Config (User's working Lightning config) ───────────────
def make_wan_config(num_frames=33, width=832, height=448):
    """User's working Wan I2V Lightning config."""
    # NOTE: start_width/start_height are pixel_size / 64 in FlatBuffer
    return GenerationConfig(
        model=WAN_HNE_I2V,
        refiner_model=WAN_LNE_I2V,
        start_width=width // 64,   # 832px → 13
        start_height=height // 64, # 448px → 7
        seed=0,
        steps=4,
        guidance_scale=1.0,
        strength=1.0,
        shift=3.0,
        sampler=Sampler.DDIM_TRAILING,
        seed_mode=SeedMode.SCALE_ALIKE,
        num_frames=num_frames,
        refiner_start=0.1,
        preserve_original_after_inpaint=True,
        causal_inference_enabled=True,
        causal_inference=17,
        causal_inference_pad=5,
        loras=[
            LoRAConfig(file=WAN_HNE_LIGHTNING, weight=0.9, mode=LoRAMode.BASE),
            LoRAConfig(file=WAN_LNE_LIGHTNING, weight=0.8, mode=LoRAMode.REFINER),
        ],
    )


# ─── Key Frame Definitions ───────────────────────────────────────────────────

KEYFRAMES = [
    {
        "name": "F1_reference",
        "source": "original",  # Use original image directly
        "prompt": None,
        "description": "Original reference image (sitting)",
    },
    {
        "name": "F2_standing",
        "source": "previous",  # Edit from previous frame
        "prompt": "she stands up from the couch, same person same face same features, indoor room",
        "strength": 0.85,
        "description": "Standing up from sitting position",
    },
    {
        "name": "F3_kneeling",
        "source": "previous",
        "prompt": "she kneels down on a yoga mat, same person same face same features, yoga studio",
        "strength": 0.80,
        "description": "Kneeling on yoga mat",
    },
    {
        "name": "F4_tabletop",
        "source": "previous",
        "prompt": "she is on hands and knees in tabletop position on yoga mat, same person same face same features",
        "strength": 0.75,
        "description": "Tabletop yoga position",
    },
    {
        "name": "F5_cow_pose",
        "source": "previous",
        "prompt": "she arches her back into yoga cow pose, head lifted, same person same face same features, yoga mat",
        "strength": 0.75,
        "description": "Cow yoga pose",
    },
]

# Video transitions between key frames
VIDEO_TRANSITIONS = [
    {
        "name": "clip1_sit_to_stand",
        "start_frame": "F1_reference",
        "prompt": "woman gracefully stands up from sitting, smooth natural movement, cinematic",
        "num_frames": 33,
    },
    {
        "name": "clip2_stand_to_kneel",
        "start_frame": "F2_standing",
        "prompt": "woman slowly kneels down onto yoga mat, deliberate movement",
        "num_frames": 37,
    },
    {
        "name": "clip3_kneel_to_tabletop",
        "start_frame": "F3_kneeling",
        "prompt": "woman moves to hands and knees, tabletop position, controlled movement",
        "num_frames": 33,
    },
    {
        "name": "clip4_tabletop_to_cow",
        "start_frame": "F4_tabletop",
        "prompt": "woman arches back into cow pose, slow controlled yoga movement, head lifted",
        "num_frames": 37,
    },
]


def run_phase1(client, output_dir):
    """Phase 1: Generate character-consistent key frames."""
    print("\n" + "=" * 60)
    print("  PHASE 1: Character-Consistent Key Frames (Qwen Image)")
    print("=" * 60)

    frames_dir = Path(output_dir) / "keyframes"
    frames_dir.mkdir(parents=True, exist_ok=True)

    # Copy original as F1
    import shutil
    f1_path = frames_dir / "F1_reference.png"
    if not f1_path.exists():
        # For F1, we just use the original reference
        shutil.copy2(REF_IMAGE, f1_path)
        print(f"\nF1: Copied reference → {f1_path}")
    else:
        print(f"\nF1: Already exists → {f1_path}")

    current_image = str(f1_path)

    for i, kf in enumerate(KEYFRAMES):
        if kf["source"] == "original":
            continue  # Already handled F1

        output_path = str(frames_dir / f"{kf['name']}.png")
        if Path(output_path).exists():
            print(f"\n{kf['name']}: Already exists, skipping → {output_path}")
            current_image = output_path
            continue

        print(f"\n{'─' * 40}")
        print(f"Generating: {kf['name']}")
        print(f"Description: {kf['description']}")
        print(f"Strength: {kf.get('strength', 0.8)}")
        print(f"Input: {current_image}")
        print(f"{'─' * 40}")

        config = make_qwen_config(strength=kf.get("strength", 0.8))
        neg_prompt = "different person, changed face, different features, different hair"

        result = client.generate(
            config=config,
            prompt=kf["prompt"],
            negative_prompt=neg_prompt,
            image_path=current_image,
        )

        if result.images:
            result.save(output_path)
            current_image = output_path
            print(f"  → Saved {kf['name']} ({result.elapsed_seconds:.1f}s)")
        else:
            print(f"  !! No output for {kf['name']}")
            break

    return frames_dir


def run_phase2(client, frames_dir, output_dir):
    """Phase 2: Generate I2V transitions between key frames."""
    print("\n" + "=" * 60)
    print("  PHASE 2: Video Transitions (Wan I2V Lightning)")
    print("=" * 60)

    video_dir = Path(output_dir) / "videos"
    video_dir.mkdir(parents=True, exist_ok=True)

    for trans in VIDEO_TRANSITIONS:
        output_path = str(video_dir / f"{trans['name']}.png")
        if Path(output_path).exists():
            print(f"\n{trans['name']}: Already exists, skipping")
            continue

        start_frame = str(frames_dir / f"{trans['start_frame']}.png")
        if not Path(start_frame).exists():
            print(f"\n{trans['name']}: Start frame not found: {start_frame}")
            continue

        print(f"\n{'─' * 40}")
        print(f"Generating: {trans['name']}")
        print(f"Start frame: {trans['start_frame']}")
        print(f"Frames: {trans['num_frames']}")
        print(f"Motion: {trans['prompt']}")
        print(f"{'─' * 40}")

        config = make_wan_config(num_frames=trans["num_frames"])

        result = client.generate(
            config=config,
            prompt=trans["prompt"],
            image_path=start_frame,
        )

        if result.images:
            result.save(output_path)
            print(f"  → Saved {trans['name']} ({result.elapsed_seconds:.1f}s)")
        else:
            print(f"  !! No output for {trans['name']}")

    return video_dir


def main():
    print("=" * 60)
    print("  Character Consistency Pipeline")
    print("  Reference: " + REF_IMAGE)
    print("  Output: " + OUTPUT_DIR)
    print("=" * 60)

    # Check reference image exists
    if not Path(REF_IMAGE).exists():
        print(f"\nERROR: Reference image not found: {REF_IMAGE}")
        sys.exit(1)

    Path(OUTPUT_DIR).mkdir(parents=True, exist_ok=True)

    with DrawThingsClient() as client:
        # Verify connection
        try:
            msg = client.echo("pipeline-start")
            print(f"\nConnected: {msg}")
        except Exception as e:
            print(f"\nConnection failed: {e}")
            print("Make sure Draw Things gRPC server is running on port 7859")
            sys.exit(1)

        # Phase 1: Key frames
        frames_dir = run_phase1(client, OUTPUT_DIR)

        # Phase 2: Video (only if user wants)
        if "--video" in sys.argv:
            run_phase2(client, frames_dir, OUTPUT_DIR)
        else:
            print("\n\nPhase 1 complete. Run with --video to generate I2V clips.")
            print("Review key frames in:", frames_dir)

    print("\n" + "=" * 60)
    print("  PIPELINE COMPLETE")
    print("=" * 60)


if __name__ == "__main__":
    main()
