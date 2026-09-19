# File-size and extraction notes

**This is not law.** The rules in force live in [CLAUDE.md](../CLAUDE.md).
If this file disagrees, CLAUDE.md wins.

The old seven-stage god-file campaign is finished. `test/baselines/god_files.json`
is `{}`. `test/hygiene/god_file_ratchet_test.dart` holds the line at **1,000**
lines. There is **no** CI job that fails every file over 500.

What remains true:

- New and extracted Dart stays under 500 lines. Do not grow a file that is
  already over — extract a cohesive piece.
- Some production files still sit over 500 after the mixed-file splits,
  including the home, ChatService, and image-gen shells. That is leftover
  size, not a license to add more.
- Generated `.g.dart` has its own ratchet
  (`test/hygiene/generated_dart_size_test.dart`). Keep
  `generate_manager: false` in `build.yaml`.
- There is no project to migrate the app to Riverpod. Riverpod is for new
  self-contained state that does not replace `ChatService`,
  `StorageService`, or the `main.dart` graph.
- One contract, one implementation. Do not leave a deprecation shim next to
  the real path.
