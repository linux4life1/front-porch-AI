# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements (unreleased — ships in the next build)

- 🎨 **Draw Things connection fixed for real** — connecting to Draw Things was a coin flip ("Test Connection" randomly failing) and image generation would show Draw Things rendering away while Front Porch never received the picture, then refuse to reconnect. One tiny byte-counting bug in how the app read Draw Things' replies caused all of it. Connection tests, model listing, single images, and expression packs now come through reliably.
- 🧠 **Memory (RAG) setup fixed on Windows** — the new built-in memory engine failed its self-test on every Windows machine ("Setup Failed" in the memory setup dialog) because of a Windows-only quirk in how the AI runtime is handed the model's file path. The engine now loads correctly on Windows — and the same fix also repairs character expressions and photo captions there, which were quietly affected by the same bug. If setup does fail, the dialog now shows the actual reason instead of a generic message.
- 🎭 **ZipVoice voice cloning** — you can now give any character a cloned voice by picking a short (3–15 second) .wav sample and typing the exact words spoken. The engine is in-process (no Python) and runs on all GPUs, including AMD. When no sample is configured, ZipVoice seamlessly falls back to your default Kokoro voice. Find the voice sample picker under "Voice Sample (ZipVoice)" in the Edit Character dialog.
- 🔧 **ZipVoice ORT crash fixed** — a packaging conflict between two ONNX Runtime copies (sherpa-onnx's ORT 1.27 vs another plugin's ORT 1.22) caused ZipVoice audio generation to crash on launch. `scripts\build_release.ps1` now patches the correct runtime automatically.
- 🔧 **Transcript display clarified** — the ZipVoice transcript picker now shows the first ~50 characters of the transcript text on re-opening the dialog, so you can immediately see the transcript is saved even when the original .txt file path isn't available.
- 🔧 Under-the-hood fixes and polish.
