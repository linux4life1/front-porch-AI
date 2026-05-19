# Character Consistency + Video Action Plan

> Incremental pipeline using ONLY your downloaded models (65GB total, zero new downloads).
> For M4 Pro 48GB using Draw Things.

**Reference image:** `~/Downloads/photo_5794272574841146840_y.jpg`
**Goal:** Same character in different poses/expressions/settings (images) + accurate action videos (e.g., sitting → yoga cow pose)

---

## Your Available Models

| Model | Size | Role in Pipeline |
|---|---|---|
| **Qwen Image 1.0 q6p** | 16 GB | Image editing + character consistency (MAIN TOOL) |
| Qwen Image Lightning 4-step LoRA | 808 MB | Fast 4-step image editing |
| Qwen Image Lightning 8-step LoRA | 808 MB | Higher quality 8-step image editing |
| Qwen Image VAE | 243 MB | Required by Qwen Image |
| **Wan 2.2 A14B HNE I2V q6p** | 11 GB | Video generation base |
| **Wan 2.2 A14B LNE I2V q6p** | 11 GB | Video generation refiner |
| Wan HNE/LNE Lightning LoRAs | 586-710 MB | 4-step fast video |
| **Wan 2.1 1.3B VACE 480p** | 1.4 GB | Pose-driven video from reference motion |
| Wan 2.2 5B TI2V q8p | 5 GB | Text/image-to-video (alternative) |
| CLIP ViT-L/14 | 582 MB | Vision encoder (used by Qwen Image for reference) |
| SigLIP 384 | 408 MB | Vision encoder |
| Qwen 2.5 VL 7B + UMT5-XXL | 13.7 GB | Text encoders (used by Wan/Qwen) |
| **RestoreFormer** | 139 MB | Face restoration post-processing |
| ParseNet | 41 MB | Face parsing (used by RestoreFormer) |

**No downloads needed. Everything below uses these models.**

---

## The Pipeline (Overview)

```
Reference Image (~/Downloads/photo_5794272574841146840_y.jpg)
    ↓
[Phase 1] Qwen Image Edit — change pose/setting while preserving identity
    ↓
[Phase 2] Generate key frame sequence (sitting → standing → mat → cow pose)
    ↓
[Phase 3] Wan I2V — animate each transition as a video clip
    ↓  (optional: VACE 1.3B for precise motion from reference video)
    ↓
[Phase 4] Chain clips + RestoreFormer face cleanup
```

---

## Phase 1: Character-Consistent Image Editing with Qwen Image

**Qwen Image 1.0** is your primary tool. It's an instruction-following image editor — you load an image, describe what to change, and it edits while preserving everything else. Much less censored than Flux Kontext.

### Step 1A: Basic Identity-Preserving Edit (Start Here)

**Time:** 5 minutes

1. Load reference image onto Draw Things canvas
2. Select model: **Qwen Image 1.0 q6p**
3. Add LoRA: **qwen_image_1.0_lightning_4_step_v2.0_lora_f16.ckpt** (weight: 1.0)
4. Settings:
   - Steps: **4** (with Lightning LoRA)
   - Guidance: **1.0**
   - Shift: **2.5**
   - Sampler: DDIM (17)
   - Strength: **80-90%** (lower = more of original preserved)
5. Prompt: `"change her pose to standing, same person same face same features, indoor studio"`
6. Generate — face and body features should be preserved with new pose

**If identity holds well** → proceed to Phase 2
**If face drifts** → try Step 1B

### Step 1B: Higher Quality Edit (8-step)

If 4-step Lightning produces face drift:

1. Switch LoRA to **qwen_image_1.0_lightning_8_step_v2.0_lora_f16.ckpt**
2. Steps: **8**
3. Guidance: **3.0** (higher guidance = more prompt-following)
4. Strength: **70-80%** (more conservative = better identity)
5. Same prompt style

8 steps gives noticeably better detail at 2x the time.

### Step 1C: Iterative Refinement (If Needed)

If a single edit changes too much at once:

1. **Small incremental changes** — don't go from "sitting on couch" to "cow pose" in one edit
2. Instead: sitting → standing (edit 1) → kneeling (edit 2) → cow pose (edit 3)
3. Each edit preserves more identity because the change is smaller
4. Use the OUTPUT of each edit as INPUT for the next

### Key Qwen Image Prompting Tips

- **Always include:** `"same person, same face, preserve identity"`
- **Be specific about what to change AND what to keep:** `"change her pose to kneeling, keep her face, hair, and clothing the same"`
- **Strength slider is critical:** 70% = subtle change, 90% = major change, 100% = basically txt2img
- **Negative prompt:** `"different person, changed face, different hair"` helps anchor identity
- **Seed locking:** If you get a good result, note the seed. Nearby seeds often produce similar quality

---

## Phase 2: Generate Key Frame Sequence

Generate 3-5 key frames showing the transition from sitting to cow pose. Each frame feeds into the next.

### The Sequence

| Frame | Edit From | Prompt | Strength |
|---|---|---|---|
| **F1** | Original image | (no edit — this IS your start frame) | — |
| **F2** | F1 | `"she stands up from the couch, same person same face, indoor room"` | 80% |
| **F3** | F2 | `"she kneels down on a yoga mat, same person same face, yoga studio"` | 80% |
| **F4** | F3 | `"she is on hands and knees in tabletop position on yoga mat, same person same face"` | 75% |
| **F5** | F4 | `"she arches her back into yoga cow pose, head lifted, same person same face, yoga mat"` | 75% |

### Process

1. Start with F1 (original reference image) on canvas
2. Run Qwen Image edit → get F2 → save F2
3. Load F2 onto canvas → edit → get F3 → save F3
4. Repeat through F5
5. **Review all frames side by side** — face should look consistent across all 5

### Quality Check

After generating all frames, compare faces:
- If faces are consistent → proceed to Phase 3
- If face drifts on one frame → regenerate that frame with lower strength (70%)
- If face drifts everywhere → try 8-step Lightning (Step 1B) for all frames

**Save all key frames to a folder:**
```
~/Pictures/CharacterFrames/
  F1_sitting.png
  F2_standing.png
  F3_kneeling.png
  F4_tabletop.png
  F5_cow_pose.png
```

---

## Phase 3: Video Generation

### Step 3A: Wan I2V Lightning (Your Working Config)

Use each key frame pair as start/end visualization for Wan I2V:

1. Load F1 (sitting) onto canvas
2. Model: **Wan 2.2 HNE I2V A14B q6p** + **LNE refiner**
3. Add Lightning LoRAs (both HNE + LNE)
4. Settings (your proven config):
   - Steps: **4**
   - Guidance: **1.0**
   - Shift: **3.0**
   - Sampler: DDIM (17)
   - Resolution: **832x448** (landscape) or **448x832** (portrait)
   - Frames: **33** (start small — ~2 seconds at 16fps)
   - causalInference: **17**, pad: **5**
   - refinerStart: **0.1**
5. Prompt: `"woman smoothly stands up from couch, natural movement, cinematic"`
6. Generate → save clip

**Key: prompt describes the MOTION, not the scene** (Wan sees the scene from the input image)

| Clip | Start Frame | Motion Prompt |
|---|---|---|
| Clip 1 | F1 (sitting) | `"woman gracefully stands up, smooth natural movement"` |
| Clip 2 | F2 (standing) | `"woman slowly kneels down onto yoga mat"` |
| Clip 3 | F3 (kneeling) | `"woman moves to hands and knees, tabletop position"` |
| Clip 4 | F4 (tabletop) | `"woman arches back into cow pose, slow controlled yoga movement"` |

### Step 3B: VACE 1.3B — Pose-Driven Video (More Precise)

You have **Wan 2.1 1.3B VACE 480p** — this lets you use a reference motion video to control the generated video.

**How to use:**

1. **Record yourself** (or find a video) doing the target motion on your phone
   - Film yourself going from sitting to cow pose
   - Even low quality / different person is fine — VACE extracts the motion, not identity
2. Load your character key frame (F1) onto canvas
3. Load reference motion video as control input
4. Model: **Wan 2.1 1.3B VACE 480p** (this is the ControlNet, needs a base Wan model)
5. The VACE model extracts depth/pose per frame and guides generation

**Limitations of your VACE model:**
- 1.3B = lower quality than 14B (softer details, less coherent faces)
- 480p max resolution
- Good enough for motion accuracy testing; may need face restoration after

**When to use VACE vs standard I2V:**
- Standard I2V: when the motion is simple and text-describable ("stands up", "walks forward")
- VACE: when the motion is specific and hard to describe ("exact yoga transition sequence")

### Step 3C: Wan 2.2 5B TI2V (Alternative)

You also have **wan_v2.2_5b_ti2v_q8p** — the 5B text/image-to-video model. This is:
- Smaller/faster than A14B
- Good for quick iteration and testing prompts
- Lower quality output
- Useful as a "draft" to verify your prompt describes the right motion before running 14B

### Step 3D: Clip Chaining

For the full sitting → cow pose sequence:

1. Generate Clip 1 (F1→F2 motion) with 33 frames
2. **Don't play** the video when done — last frame stays on canvas
3. That last frame becomes start frame for Clip 2
4. Generate Clip 2 with 33-41 frames (vary count to avoid repetition)
5. Repeat through Clip 4
6. Export all: Version History → select all → export as video

**Vary frame counts:** 33, 37, 41 to prevent repetitive motion artifacts.

---

## Phase 4: Polish

### Step 4A: Face Restoration (RestoreFormer)

You have **restoreformer_v1.0_f16.ckpt** + **parsenet_v1.0_f16.ckpt**.

If any video frames have face artifacts:
- In Draw Things config: set `faceRestoration: true`
- This applies RestoreFormer automatically during generation
- Can also be applied post-hoc to individual frames

### Step 4B: Color/Brightness Consistency

When chaining clips, color can drift between transitions:

```bash
# Extract frames from each clip
mkdir -p frames_in frames_out
ffmpeg -i clip1.mp4 frames_in/clip1_%05d.png
ffmpeg -i clip2.mp4 frames_in/clip2_%05d.png

# Color-lock to first frame (if color_lock.py exists)
python3 color_lock.py

# Reassemble
ffmpeg -framerate 16 -i frames_out/%05d.png -pix_fmt yuv420p final.mp4
```

### Step 4C: Concatenate Final Video

```bash
# Create file list
echo "file 'clip1.mp4'" > concat.txt
echo "file 'clip2.mp4'" >> concat.txt
echo "file 'clip3.mp4'" >> concat.txt
echo "file 'clip4.mp4'" >> concat.txt

# Concat without re-encoding
ffmpeg -f concat -safe 0 -i concat.txt -c copy full_sequence.mp4
```

---

## Recommended Execution Order

All using models you already have. Zero downloads.

| Step | What | Models Used | Time |
|---|---|---|---|
| **1** | Edit reference image to standing pose (Qwen Image 4-step) | Qwen Image + Lightning 4-step LoRA | 2-3 min |
| **2** | Check face consistency — if OK, continue; if not, try 8-step | Qwen Image + Lightning 8-step LoRA | 2-5 min |
| **3** | Generate 5 key frames (sitting → standing → kneeling → tabletop → cow) | Qwen Image | 15-20 min |
| **4** | Test: I2V one transition (F1→F2) with your Lightning config | Wan A14B HNE+LNE + Lightning LoRAs | 5-10 min |
| **5** | I2V all 4 transitions | Wan A14B HNE+LNE + Lightning LoRAs | 20-40 min |
| **6** | Chain clips + face restoration | RestoreFormer + FFmpeg | 15 min |
| **7** | (Optional) Try VACE with phone-recorded reference motion | Wan 2.1 1.3B VACE 480p | 30 min |

**Start with Step 1.** If Qwen Image preserves the character well at 4-step Lightning, the whole pipeline can be done in under 2 hours with no downloads.

---

## Quick Reference: Qwen Image Config

```
Model: qwen_image_1.0_q6p.ckpt
LoRA: qwen_image_1.0_lightning_4_step_v2.0_lora_f16.ckpt (weight: 1.0)
Steps: 4
Guidance: 1.0
Shift: 2.5
Sampler: 17 (DDIM)
Strength: 75-85%
Negative: "different person, changed face, different features"
```

## Quick Reference: Wan I2V Config (Your Working Setup)

```
Model: wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt
Refiner: wan_v2.2_a14b_lne_i2v_q6p_svd.ckpt
LoRA (HNE): wan_v2.2_a14b_hne_i2v_lightning_v1.0_lora_f16.ckpt
LoRA (LNE): wan_v2.2_a14b_lne_i2v_lightning_v1.0_lora_f16.ckpt
Steps: 4
Guidance: 1.0
Shift: 3.0
Sampler: 17 (DDIM)
Resolution: 832x448 (landscape) or 448x832 (portrait)
Frames: 33
causalInference: 17
pad: 5
refinerStart: 0.1
```

---

## On Censorship

- **Qwen Image 1.0**: Alibaba model — has some Chinese political censorship but is relatively permissive for artistic/body content. Much less restrictive than Flux Kontext for poses, expressions, and clothing changes.
- **Flux Kontext Dev**: (NOT downloaded, NOT needed) Heavily censored by Black Forest Labs. Blocks most NSFW/explicit content. Would be limiting for some artistic poses.
- **Wan I2V**: Alibaba — similar to Qwen, minimal artistic censorship. May refuse some explicit prompts but generally cooperative for poses, yoga, athletic content.
- **Draw Things advantage**: Running locally means no cloud-side filtering. The censorship is baked into model weights, not an API filter, but it's still less aggressive than cloud services.

---

## Key Tips

1. **One change at a time** — change pose OR setting OR clothing, not all at once
2. **Always include identity anchors** in Qwen Image prompts: "same person, same face"
3. **Strength 75-85%** for Qwen Image — too high loses identity, too low doesn't change enough
4. **Portrait orientation (448x832)** for standing/yoga poses in video
5. **Prompt the MOTION for video**, not the scene — Wan I2V sees the scene from the image
6. **Vary frame counts** (33, 37, 41) when chaining clips to avoid repetitive motion
7. **Pre-crop input images** to exact generation dimensions before loading
8. **Use 5B TI2V as a quick draft** before committing to 14B generation time
