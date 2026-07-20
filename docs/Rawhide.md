# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements (unreleased — ships in the next build)

- 🐛 **Fixed: global background leaking into unt-themed chats** — if you had ever set chat background in the global Settings dialog, every conversation that didn't have its own per-chat theme would show that background, even when it didn't make sense. Unthemed chats now correctly show no background, and only chats with an explicit theme override display their scene.

- 🎨 **Per-chat visual themes** — every conversation can now have its own look. Pick from 10 built-in presets (Fantasy, Galactic, Neon Grid, Sakura, Noir, Enchanted Forest, Ocean Depths, Cyberpunk, Cottagecore, Steampunk) or customize every detail: bubble colors, text colors, font, background scene, and decorative border style. Your settings carry over when you start a new chat with the same character or group, and each chat remembers its own theme independently.
- 🎯 **Regenerating a reply now rolls back its quest changes** — if a character proposed a new objective or checked off a quest step during a reply you then regenerated, those changes used to stick around even though the moment they came from was gone. Now they're undone along with the rejected reply, and the new reply earns its own — your hand-made objectives and manual "Check now" results are never touched.
- 🎨 **Draw Things connection fixed for real** — connecting to Draw Things was a coin flip ("Test Connection" randomly failing) and image generation would show Draw Things rendering away while Front Porch never received the picture, then refuse to reconnect. One tiny byte-counting bug in how the app read Draw Things' replies caused all of it. Connection tests, model listing, single images, and expression packs now come through reliably.
- 🧠 **Memory (RAG) setup fixed on Windows** — the new built-in memory engine failed its self-test on every Windows machine ("Setup Failed" in the memory setup dialog) because of a Windows-only quirk in how the AI runtime is handed the model's file path. The engine now loads correctly on Windows — and the same fix also repairs character expressions and photo captions there, which were quietly affected by the same bug. If setup does fail, the dialog now shows the actual reason instead of a generic message.
- 🔧 Under-the-hood fixes and polish.
