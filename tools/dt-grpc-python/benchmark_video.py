"""
Wan I2V Lightning Speed Benchmark

Tests different configurations to find the fastest 16→81 frame video generation.
Levers: TeaCache, causal inference chunk/pad, resolution, steps.
"""

import sys
import time
import json
from dataclasses import asdict
from pathlib import Path

from client import (
    DrawThingsClient, GenerationConfig, LoRAConfig,
    Sampler, SeedMode, LoRAMode,
    WAN_HNE_I2V, WAN_LNE_I2V, WAN_HNE_LIGHTNING, WAN_LNE_LIGHTNING,
)

REF_IMAGE = Path("~/Downloads/photo_5794272574841146840_y.jpg").expanduser()
OUTPUT_DIR = Path("~/Pictures/VideoSpeedBench").expanduser()
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

PROMPT = "woman gracefully stands up from sitting, smooth natural movement, cinematic, indoor room"


def make_config(
    num_frames=16,
    width=832, height=448,
    steps=4,
    tea_cache=False, tea_cache_threshold=0.15,
    causal_inference=17, causal_inference_pad=5,
    sampler=Sampler.DDIM_TRAILING,
    shift=3.0,
    guidance_scale=1.0,
    hne_lora_weight=0.9,
    lne_lora_weight=0.8,
    refiner_start=0.1,
) -> GenerationConfig:
    return GenerationConfig(
        model=WAN_HNE_I2V,
        refiner_model=WAN_LNE_I2V,
        start_width=width // 64,
        start_height=height // 64,
        steps=steps,
        guidance_scale=guidance_scale,
        strength=1.0,
        shift=shift,
        sampler=sampler,
        seed_mode=SeedMode.SCALE_ALIKE,
        num_frames=num_frames,
        refiner_start=refiner_start,
        preserve_original_after_inpaint=True,
        causal_inference_enabled=causal_inference > 0,
        causal_inference=causal_inference,
        causal_inference_pad=causal_inference_pad,
        tea_cache=tea_cache,
        tea_cache_threshold=tea_cache_threshold,
        tea_cache_start=2,
        tea_cache_end=-1,
        tea_cache_max_skip_steps=3,
        loras=[
            LoRAConfig(file=WAN_HNE_LIGHTNING, weight=hne_lora_weight, mode=LoRAMode.BASE),
            LoRAConfig(file=WAN_LNE_LIGHTNING, weight=lne_lora_weight, mode=LoRAMode.REFINER),
        ],
    )


def run_bench(client, name, config, save_frames=False):
    """Run one benchmark and return timing."""
    print(f"\n{'='*60}")
    print(f"  BENCH: {name}")
    print(f"  {config.num_frames} frames, {config.start_width*64}x{config.start_height*64}")
    print(f"  steps={config.steps}, tea_cache={config.tea_cache}")
    print(f"  causal_inference={config.causal_inference}, pad={config.causal_inference_pad}")
    print(f"{'='*60}")

    start = time.time()
    result = client.generate(
        config=config,
        prompt=PROMPT,
        image_path=str(REF_IMAGE),
        verbose=True,
    )
    elapsed = time.time() - start

    n_frames = len(result.images)
    fps = n_frames / elapsed if elapsed > 0 else 0
    sec_per_frame = elapsed / n_frames if n_frames > 0 else 0

    print(f"\n  RESULT: {n_frames} frames in {elapsed:.1f}s")
    print(f"  Speed:  {fps:.2f} frames/sec, {sec_per_frame:.1f}s/frame")

    if save_frames and result.images:
        out = OUTPUT_DIR / name
        out.mkdir(parents=True, exist_ok=True)
        result.save(str(out / "frame_000.png"), index=0)

    return {
        "name": name,
        "num_frames": config.num_frames,
        "elapsed_s": round(elapsed, 1),
        "n_output": n_frames,
        "fps": round(fps, 3),
        "sec_per_frame": round(sec_per_frame, 1),
        "steps": config.steps,
        "tea_cache": config.tea_cache,
        "tea_cache_threshold": config.tea_cache_threshold,
        "causal_inference": config.causal_inference,
        "causal_inference_pad": config.causal_inference_pad,
        "resolution": f"{config.start_width*64}x{config.start_height*64}",
    }


def main():
    if not REF_IMAGE.exists():
        print(f"Reference image not found: {REF_IMAGE}")
        sys.exit(1)

    client = DrawThingsClient()
    try:
        msg = client.echo("speed-bench")
        print(f"Connected: {msg}")
    except Exception as e:
        print(f"Connection failed: {e}")
        sys.exit(1)

    results = []

    # ─── 16-Frame Benchmarks ────────────────────────────────────────
    print("\n" + "#"*60)
    print("  16-FRAME SPEED TESTS")
    print("#"*60)

    # 1. Baseline: your working config
    results.append(run_bench(client, "16f_baseline",
        make_config(num_frames=16), save_frames=True))

    # 2. TeaCache on (threshold=0.15)
    results.append(run_bench(client, "16f_teacache_015",
        make_config(num_frames=16, tea_cache=True, tea_cache_threshold=0.15)))

    # 3. TeaCache aggressive (threshold=0.25)
    results.append(run_bench(client, "16f_teacache_025",
        make_config(num_frames=16, tea_cache=True, tea_cache_threshold=0.25)))

    # 4. No causal inference (process all frames at once)
    results.append(run_bench(client, "16f_no_causal",
        make_config(num_frames=16, causal_inference=0, causal_inference_pad=0)))

    # 5. Causal inference=16 pad=0 (no overlap)
    results.append(run_bench(client, "16f_causal16_pad0",
        make_config(num_frames=16, causal_inference=16, causal_inference_pad=0)))

    # 6. TeaCache + no causal
    results.append(run_bench(client, "16f_teacache_no_causal",
        make_config(num_frames=16, tea_cache=True, tea_cache_threshold=0.15,
                    causal_inference=0, causal_inference_pad=0)))

    # 7. TeaCache + causal pad=0
    results.append(run_bench(client, "16f_teacache_causal_pad0",
        make_config(num_frames=16, tea_cache=True, tea_cache_threshold=0.15,
                    causal_inference=17, causal_inference_pad=0)))

    # 8. Lower res 640x384 (if 832x448 is slow)
    results.append(run_bench(client, "16f_lowres_640x384",
        make_config(num_frames=16, width=640, height=384)))

    # ─── Summary ────────────────────────────────────────────────────
    print("\n" + "="*70)
    print(f"  {'Name':<30} {'Time':>7} {'FPS':>7} {'s/frm':>7}")
    print("-"*70)
    for r in results:
        print(f"  {r['name']:<30} {r['elapsed_s']:>6.1f}s {r['fps']:>7.3f} {r['sec_per_frame']:>6.1f}s")
    print("="*70)

    # Save results
    results_file = OUTPUT_DIR / "benchmark_results.json"
    with open(results_file, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nResults saved: {results_file}")

    # Find fastest
    fastest = min(results, key=lambda r: r["elapsed_s"])
    print(f"\nFastest: {fastest['name']} — {fastest['elapsed_s']}s ({fastest['fps']:.3f} fps)")

    client.close()


if __name__ == "__main__":
    main()
