//@api-1.0
//
// Character Consistency Pipeline — Qwen Image Edit + Wan I2V
// Generates key frames with character consistency, then animates transitions.
//
// USAGE:
//   1. Load your reference image onto the Draw Things canvas
//   2. Run this script from the scripting menu
//   3. It will generate key frames (Phase 1) then optionally video clips (Phase 2)
//
// MODELS REQUIRED (all already downloaded):
//   - qwen_image_1.0_q6p.ckpt
//   - qwen_image_1.0_lightning_4_step_v2.0_lora_f16.ckpt
//   - wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt (for video)
//   - wan_v2.2_a14b_lne_i2v_q6p_svd.ckpt (for video)
//   - wan_v2.2_a14b_hne_i2v_lightning_v1.0_lora_f16.ckpt (for video)
//   - wan_v2.2_a14b_lne_i2v_lightning_v1.0_lora_f16.ckpt (for video)

// ─── Models ──────────────────────────────────────────────────────────
var QWEN_IMAGE = "qwen_image_1.0_q6p.ckpt";
var QWEN_LIGHTNING_4 = "qwen_image_1.0_lightning_4_step_v2.0_lora_f16.ckpt";
var WAN_HNE = "wan_v2.2_a14b_hne_i2v_q6p_svd.ckpt";
var WAN_LNE = "wan_v2.2_a14b_lne_i2v_q6p_svd.ckpt";
var WAN_HNE_LIGHTNING = "wan_v2.2_a14b_hne_i2v_lightning_v1.0_lora_f16.ckpt";
var WAN_LNE_LIGHTNING = "wan_v2.2_a14b_lne_i2v_lightning_v1.0_lora_f16.ckpt";

// ─── UI ──────────────────────────────────────────────────────────────
var userSelection = requestFromUser("Character Pipeline", "Start", function() {
  return [
    this.section("Phase", "Choose what to generate.", [
      this.segmented(0, [
        "Key Frames Only",
        "Key Frames + Video",
        "Video Only (frames exist)",
        "Single Edit Test"
      ]),
    ]),
    this.section("Character Edit Settings", "Qwen Image edit parameters.", [
      this.slider(85, this.slider.fractional(0), 50, 100, "Edit Strength %"),
      this.slider(4, this.slider.fractional(0), 1, 8, "Steps"),
    ]),
    this.section("Video Settings", "Wan I2V parameters (if generating video).", [
      this.slider(33, this.slider.fractional(0), 9, 81, "Frames per clip"),
      this.segmented(0, ["Landscape 832x448", "Portrait 448x832"]),
    ]),
    this.section("Prompts", "Edit the key frame prompts if desired.", [
      this.textField(
        "she stands up from the couch, same person same face same features, indoor room",
        "F2: Standing", true, 80
      ),
      this.textField(
        "she kneels down on a yoga mat, same person same face same features, yoga studio",
        "F3: Kneeling", true, 80
      ),
      this.textField(
        "she is on hands and knees in tabletop position on yoga mat, same person same face same features",
        "F4: Tabletop", true, 80
      ),
      this.textField(
        "she arches her back into yoga cow pose, head lifted, same person same face same features, yoga mat",
        "F5: Cow Pose", true, 80
      ),
    ]),
    this.section("Output", "Save location.", [
      this.textField("CharacterPipeline", "Output folder name", false, 20),
    ]),
  ];
});

// ─── Parse UI ────────────────────────────────────────────────────────
var phase = userSelection[0][0];
var editStrength = userSelection[1][0] / 100.0;
var editSteps = userSelection[1][1];
var videoFrames = userSelection[2][0];
var videoOrientation = userSelection[2][1];
var promptF2 = userSelection[3][0];
var promptF3 = userSelection[3][1];
var promptF4 = userSelection[3][2];
var promptF5 = userSelection[3][3];
var outputFolder = userSelection[4][0];

var videoW = videoOrientation === 0 ? 832 : 448;
var videoH = videoOrientation === 0 ? 448 : 832;

var outputPath = filesystem.pictures.path + "/" + outputFolder;
var negPrompt = "different person, changed face, different features, different hair";

// ─── Key Frame Definitions ───────────────────────────────────────────
var keyframes = [
  { name: "F2_standing",  prompt: promptF2, strength: editStrength },
  { name: "F3_kneeling",  prompt: promptF3, strength: Math.max(editStrength - 0.05, 0.5) },
  { name: "F4_tabletop",  prompt: promptF4, strength: Math.max(editStrength - 0.10, 0.5) },
  { name: "F5_cow_pose",  prompt: promptF5, strength: Math.max(editStrength - 0.10, 0.5) },
];

// Video transition prompts (describe MOTION, not scene)
var videoTransitions = [
  { name: "clip1_sit_to_stand",     frames: videoFrames,     prompt: "woman gracefully stands up from sitting, smooth natural movement, cinematic" },
  { name: "clip2_stand_to_kneel",   frames: videoFrames + 4, prompt: "woman slowly kneels down onto yoga mat, deliberate movement" },
  { name: "clip3_kneel_to_tabletop",frames: videoFrames,     prompt: "woman moves to hands and knees, tabletop position, controlled movement" },
  { name: "clip4_tabletop_to_cow",  frames: videoFrames + 4, prompt: "woman arches back into cow pose, slow controlled yoga movement, head lifted" },
];

// ─── Helper: Apply Qwen Image Config ────────────────────────────────
function applyQwenConfig(config, strength) {
  config.model = QWEN_IMAGE;
  config.refinerModel = QWEN_IMAGE;
  config.width = 512;
  config.height = 1024;
  config.steps = editSteps;
  config.guidanceScale = 1.0;
  config.strength = strength;
  config.shift = 3;
  config.sampler = 17;  // UniPCTrailing
  config.seedMode = 2;  // ScaleAlike
  config.seed = -1;     // Random
  config.batchCount = 1;
  config.batchSize = 1;
  config.refinerStart = 0.1;
  config.preserveOriginalAfterInpaint = true;
  config.resolutionDependentShift = false;
  config.cfgZeroStar = false;
  config.tiledDiffusion = false;
  config.tiledDecoding = false;
  config.loras = [{ file: QWEN_LIGHTNING_4, weight: 1.0, mode: "all" }];
  config.controls = [];
}

// ─── Helper: Apply Wan I2V Config ────────────────────────────────────
function applyWanConfig(config, numFrames) {
  config.model = WAN_HNE;
  config.refinerModel = WAN_LNE;
  config.width = videoW;
  config.height = videoH;
  config.steps = 4;
  config.guidanceScale = 1.0;
  config.strength = 1.0;
  config.shift = 3;
  config.sampler = 17;
  config.seedMode = 2;
  config.seed = -1;
  config.numFrames = numFrames;
  config.refinerStart = 0.1;
  config.preserveOriginalAfterInpaint = true;
  config.causalInferenceEnabled = true;
  config.causalInference = 17;
  config.causalInferencePad = 5;
  config.cfgZeroStar = false;
  config.tiledDiffusion = false;
  config.tiledDecoding = false;
  config.loras = [
    { file: WAN_HNE_LIGHTNING, weight: 0.9, mode: "base" },
    { file: WAN_LNE_LIGHTNING, weight: 0.8, mode: "refiner" },
  ];
  config.controls = [];
}

// ─── Check Models ────────────────────────────────────────────────────
var requiredModels = [QWEN_IMAGE, QWEN_LIGHTNING_4];
if (phase === 1 || phase === 2) {
  requiredModels.push(WAN_HNE, WAN_LNE, WAN_HNE_LIGHTNING, WAN_LNE_LIGHTNING);
}
if (!pipeline.areModelsDownloaded(requiredModels)) {
  console.log("Downloading required models...");
  pipeline.downloadBuiltins(requiredModels);
}

// ─── Main ────────────────────────────────────────────────────────────
console.log("====================================================");
console.log("  Character Consistency Pipeline");
console.log("====================================================");
console.log("Phase:     " + ["Key Frames", "Key Frames + Video", "Video Only", "Single Test"][phase]);
console.log("Strength:  " + (editStrength * 100).toFixed(0) + "%");
console.log("Steps:     " + editSteps);
if (phase === 1 || phase === 2) {
  console.log("Video:     " + videoW + "x" + videoH + " @ " + videoFrames + " frames");
}
console.log("Output:    " + outputPath);
console.log("----------------------------------------------------");

var totalStart = Date.now();

// ─── Phase 0: Single Edit Test ──────────────────────────────────────
if (phase === 3) {
  console.log("\n=== SINGLE EDIT TEST ===");
  console.log("Editing with prompt: " + promptF2);

  var config = pipeline.configuration;
  applyQwenConfig(config, editStrength);

  var startTime = Date.now();
  pipeline.run({ configuration: config, prompt: promptF2, negativePrompt: negPrompt });
  var elapsed = Math.round((Date.now() - startTime) / 1000);

  var filename = outputPath + "/test_edit_" + Date.now() + ".png";
  canvas.saveImage(filename, true);

  console.log("  Time: " + elapsed + "s");
  console.log("  Saved: " + filename);
  console.log("\nCheck the output. If the face is consistent, run the full pipeline.");
  console.log("====================================================");
}

// ─── Phase 1: Generate Key Frames ───────────────────────────────────
if (phase === 0 || phase === 1) {
  console.log("\n=== PHASE 1: KEY FRAMES (Qwen Image Edit) ===\n");

  // Save F1 (current canvas = reference image)
  var f1Path = outputPath + "/F1_reference.png";
  canvas.saveImage(f1Path, true);
  console.log("F1 (reference): saved → " + f1Path);

  for (var i = 0; i < keyframes.length; i++) {
    var kf = keyframes[i];
    console.log("\n--- " + kf.name + " ---");
    console.log("Prompt: " + kf.prompt);
    console.log("Strength: " + (kf.strength * 100).toFixed(0) + "%");

    var config = pipeline.configuration;
    applyQwenConfig(config, kf.strength);

    var startTime = Date.now();
    pipeline.run({ configuration: config, prompt: kf.prompt, negativePrompt: negPrompt });
    var elapsed = Math.round((Date.now() - startTime) / 1000);

    var filename = outputPath + "/" + kf.name + ".png";
    canvas.saveImage(filename, true);

    console.log("  Time: " + elapsed + "s");
    console.log("  Saved: " + filename);

    // The output stays on canvas → becomes input for next edit
    // This is the key to progressive character editing
  }

  console.log("\n=== PHASE 1 COMPLETE ===");
  console.log("Key frames saved to: " + outputPath);
}

// ─── Phase 2: Generate Video Clips ──────────────────────────────────
if (phase === 1 || phase === 2) {
  console.log("\n=== PHASE 2: VIDEO CLIPS (Wan I2V Lightning) ===\n");

  // For each transition, load the start frame and generate video
  var frameNames = ["F1_reference", "F2_standing", "F3_kneeling", "F4_tabletop"];

  for (var i = 0; i < videoTransitions.length; i++) {
    var trans = videoTransitions[i];
    console.log("\n--- " + trans.name + " ---");
    console.log("Start frame: " + frameNames[i]);
    console.log("Motion: " + trans.prompt);
    console.log("Frames: " + trans.frames);

    // Load the start frame back onto canvas
    var startFramePath = outputPath + "/" + frameNames[i] + ".png";
    canvas.loadImage(startFramePath);

    var config = pipeline.configuration;
    applyWanConfig(config, trans.frames);

    var startTime = Date.now();
    pipeline.run({ configuration: config, prompt: trans.prompt });
    var elapsed = Math.round((Date.now() - startTime) / 1000);

    var filename = outputPath + "/" + trans.name + ".png";
    canvas.saveImage(filename, true);

    var minutes = Math.round(elapsed / 6) / 10;
    console.log("  Time: " + minutes + " min (" + elapsed + "s)");
    console.log("  Saved: " + filename);
  }

  console.log("\n=== PHASE 2 COMPLETE ===");
}

// ─── Summary ─────────────────────────────────────────────────────────
var totalElapsed = Math.round((Date.now() - totalStart) / 1000);
var totalMinutes = Math.round(totalElapsed / 6) / 10;

console.log("\n====================================================");
console.log("  PIPELINE COMPLETE");
console.log("----------------------------------------------------");
console.log("  Total time: " + totalMinutes + " min (" + totalElapsed + "s)");
console.log("  Output:     " + outputPath);
console.log("====================================================");
