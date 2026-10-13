# Windows ONNX runtime compatibility

Kokoro, Piper and Whisper use Sherpa in the Windows application process. Other
ONNX consumers use the same `onnxruntime.dll` module name. The Windows install
step previously copied Sherpa's runtime, then overwrote it with the older runtime
from native assets. Sherpa's pinned build requests API 28; an incompatible runtime
can return a null API pointer that leads to a native access violation.

## Implementation

The Windows CMake install selects Sherpa's runtime and provider DLLs once,
filters competing runtime files from plugin and native-asset copying, and fails
configuration if Sherpa's runtime is missing or ambiguous. No dependencies change.

Before binding Sherpa on Windows, the shared loader inspects an already-loaded
runtime or preloads the bundled runtime with a restricted DLL search path. It
checks `OrtGetApiBase` and API 28 and throws a descriptive error for incompatible
or missing libraries. It keeps the selected module loaded for other ONNX users.
The API floor must be reviewed when updating Sherpa's native dependency.

This covers all callers of `initSherpaBindings`, including the Kokoro/Piper TTS
and Whisper STT workers. macOS and Linux loading behavior is unchanged. Shared
server-side speech benefits from the same Windows fix; no UI controls change.
Chat-path matrices are not applicable: no chat state, prompt, orchestration,
database or storage behavior changes.

## Verification

On Windows, the five native tests use real DLLs in isolated processes: reject an
already-loaded older runtime, accept the matching bundle, initialize the other
ONNX binding before and after Sherpa, and reject missing or older bundled files.
Disabling the guard call makes the loaded-runtime rejection test fail; restoring
it passes. These cases also pass against the finished Release bundle. Its runtime
hash matches Sherpa's source runtime. The Windows Release build and changed-file
analysis pass, as do the hygiene ratchets and dependency-floor gate.

The speech-loader regression run passes 13 tests and skips five tests needing
model fixtures. One unchanged macOS path test fails on Windows because it joins
with host-platform separators and expects forward slashes. No existing tests or
baselines are changed. Full-suite, macOS/Linux builds and new end-to-end speech
synthesis are not verified in this extracted PR. The original local fix recorded
synthetic speech reproduction; no primary-profile data is needed for these checks.

Set `FP_TEST_OLD_ORT` to a real older Windows `onnxruntime.dll`,
`FP_TEST_SHERPA_DIR` to Sherpa's native library directory and optionally
`FP_TEST_DART` to the Dart executable to run the native tests. Missing fixtures
produce explicit skips.

## Local check

1. Start the rebuilt Windows executable with an isolated test profile and Kokoro enabled.
2. Use a voice preview and confirm a short synthetic sentence produces audio.
3. Repeat several previews and confirm the process stays running; check Whisper
   or Piper too if their models are installed in the isolated environment.
