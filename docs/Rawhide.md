# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements (unreleased — ships in the next build)

- 🎨 **Draw Things connection fixed for real** — connecting to Draw Things was a coin flip ("Test Connection" randomly failing) and image generation would show Draw Things rendering away while Front Porch never received the picture, then refuse to reconnect. One tiny byte-counting bug in how the app read Draw Things' replies caused all of it. Connection tests, model listing, single images, and expression packs now come through reliably.
- 🧠 **Memory (RAG) setup fixed on Windows** — the new built-in memory engine failed its self-test on every Windows machine ("Setup Failed" in the memory setup dialog) because of a Windows-only quirk in how the AI runtime is handed the model's file path. The engine now loads correctly on Windows — and the same fix also repairs character expressions and photo captions there, which were quietly affected by the same bug. If setup does fail, the dialog now shows the actual reason instead of a generic message.
- 🔧 Under-the-hood fixes and polish.
