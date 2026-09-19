# File-size and extraction notes

**This is not law.** The rules in force live in [CLAUDE.md](../CLAUDE.md).
If this file disagrees, CLAUDE.md wins.

The old seven-stage god-file campaign is finished. `test/baselines/god_files.json`
is `{}`. `test/hygiene/god_file_ratchet_test.dart` holds the line at **500**
lines for handwritten Dart under `lib/`. That is the CI gate. Do not add
baseline leftovers — split the file.

What remains true:

- New and extracted Dart stays under 500 lines. Extract a cohesive piece;
  do not grow a file toward the bar.
- Generated `.g.dart` (including `lib/database/database.g.dart`) is excluded
  from the handwritten ratchet and owned by
  `test/hygiene/generated_dart_size_test.dart`. Keep
  `generate_manager: false` in `build.yaml`. Do not invent a second
  500-line gate.
- There is no project to migrate the app to Riverpod. Riverpod is for new
  self-contained state that does not replace `ChatService`,
  `StorageService`, or the `main.dart` graph.
- One contract, one implementation. Do not leave a deprecation shim next to
  the real path.
