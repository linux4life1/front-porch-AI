"""
Round 3: Scale-up benchmark — best configs from Round 2 at 16→81 frames.

Round 2 winner: 5B ti2v at 4 steps, 640x384 = 30.7s for 9 frames (3.4s/frame)
Top 3: 5B_4s_640, 5B_10s_576, 5B_6s_640_nocausal
"""

import sys
import time
import json
from pathlib import Path

from client import (
    DrawThingsClient, GenerationConfig, LoRAConfig,
    Sampler, SeedMode, LoRAMode,
    WAN_HNE_I2V, WAN_LNE_I2V, WAN_HNE_LIGHTNING, WAN_LNE_LIGHTNING,
    WAN_5B_TI2V,
)

REF_IMAGE = Path("~/Downloads/photo_5794272574841146840_y.jpg").expanduser()
OUTPUT_DIR = Path("~/Pictures/VideoSpeedBench/round3").expanduser()
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

PROMPT = "woman gracefully stands up from sitting, smooth natural movement, cinematic, indoor room"


def make_5b_config(
    num_frames=16, width=640, height=384, steps=4,
    causal_inference=17, causal_inference_pad=5,
    sampler=Sampler.DDIM_TRAILING, shift=3.0, guidance_scale=1.0,
) -> GenerationConfig:
    """5B ti2v model — no Lightning LoRA, no refiner."""
    return GenerationConfig(
        model=WAN_5B_TI2V,
        start_width=width // 64,
        start_height=height // 64,
        steps=steps,
        guidance_scale=guidance_scale,
        strength=1.0,
        shift=shift,
        sampler=sampler,
        seed_mode=SeedMode.SCALE_ALIKE,
        num_frames=num_frames,
        preserve_original_after_inpaint=True,
        causal_inference_enabled=causal_inference > 0,
        causal_inference=causal_inference,
        causal_inference_pad=causal_inference_pad,
    )


def make_a14b_config(
    num_frames=16, width=640, height=384, steps=4,
    causal_inference=17, causal_inference_pad=5,
) -> GenerationConfig:
    """A14B Lightning — the original baseline for comparison."""
    return GenerationConfig(
        model=WAN_HNE_I2V,
        refiner_model=WAN_LNE_I2V,
        start_width=width // 64,
        start_height=height // 64,
        steps=steps,
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


def run_bench(client, name, config, save_first_frame=False):
    """Run one benchmark and return timing."""
    res_str = f"{config.start_width*64}x{config.start_height*64}"
    print(f"\n  {name}: {config.num_frames}f {res_str} {config.steps}step ...", end=" ", flush=True)

    start = time.time()
    result = client.generate(
        config=config,
        prompt=PROMPT,
        image_path=str(REF_IMAGE),
        verbose=False,
    )
    elapsed = time.time() - start

    n_frames = len(result.images)
    sec_per_frame = elapsed / n_frames if n_frames > 0 else 0

    print(f"{n_frames}f in {elapsed:.1f}s ({sec_per_frame:.1f}s/f)")

    if save_first_frame and result.images:
        out_path = OUTPUT_DIR / f"{name}.png"
        result.save(str(out_path), index=0)
        print(f"    Saved: {out_path}")

    return {
        "name": name,
        "req_frames": config.num_frames,
        "out_frames": n_frames,
        "elapsed_s": round(elapsed, 1),
        "sec_per_frame": round(sec_per_frame, 1),
        "steps": config.steps,
        "resolution": res_str,
        "model": "5B" if "5b" in (config.model or "").lower() else "A14B",
    }


def main():
    if not REF_IMAGE.exists():
        print(f"Reference image not found: {REF_IMAGE}")
        sys.exit(1)

    client = DrawThingsClient()
    try:
        msg = client.echo("round3")
        print(f"Connected: {msg}")
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

    results = []

    # ─── Part 1: Top configs at 16 frames ─────────────────────────────
    print("\n" + "#"*60)
    print("  PART 1: TOP CONFIGS AT 16 FRAMES")
    print("#"*60)

    # Winner: 5B 4-step 640x384
    results.append(run_bench(client, "5B_4s_640_16f",
        make_5b_config(num_frames=16, width=640, height=384, steps=4),
        save_first_frame=True))

    # Runner-up: 5B 10-step 576x320
    results.append(run_bench(client, "5B_10s_576_16f",
        make_5b_config(num_frames=16, width=576, height=320, steps=10),
        save_first_frame=True))

    # 5B 4-step 832x448 (full res, for quality comparison)
    results.append(run_bench(client, "5B_4s_832_16f",
        make_5b_config(num_frames=16, width=832, height=448, steps=4),
        save_first_frame=True))

    # A14B Lightning baseline at 640x384 for comparison
    results.append(run_bench(client, "A14B_4s_640_16f",
        make_a14b_config(num_frames=16, width=640, height=384, steps=4),
        save_first_frame=True))

    # ─── Part 2: Scale-up with fastest config ─────────────────────────
    print("\n" + "#"*60)
    print("  PART 2: SCALE TO 33/49/81 FRAMES (5B 4-step 640x384)")
    print("#"*60)

    for nf in [33, 49, 81]:
        results.append(run_bench(client, f"5B_4s_640_{nf}f",
            make_5b_config(num_frames=nf, width=640, height=384, steps=4),
            save_first_frame=True))

    # Also test 81f at higher res for quality
    results.append(run_bench(client, "5B_4s_832_81f",
        make_5b_config(num_frames=81, width=832, height=448, steps=4),
        save_first_frame=True))

    # A14B Lightning at 81 frames for comparison
    results.append(run_bench(client, "A14B_4s_640_81f",
        make_a14b_config(num_frames=81, width=640, height=384, steps=4),
        save_first_frame=True))

    # ─── Summary ──────────────────────────────────────────────────────
    print("\n" + "="*75)
    print(f"  {'Config':<25} {'Model':>5} {'Req':>4} {'Out':>4} {'Time':>7} {'s/frm':>6}")
    print("-"*75)
    for r in sorted(results, key=lambda x: x["sec_per_frame"]):
        print(f"  {r['name']:<25} {r['model']:>5} {r['req_frames']:>4} {r['out_frames']:>4} {r['elapsed_s']:>6.1f}s {r['sec_per_frame']:>5.1f}s")
    print("="*75)

    # Save results
    results_file = OUTPUT_DIR / "round3_results.json"
    with open(results_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved: {results_file}")
    print(f"Sample frames saved to: {OUTPUT_DIR}")

    client.close()


if __name__ == "__main__":
    main()
