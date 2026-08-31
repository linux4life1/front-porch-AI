# Dependency guard — why these tests exist, and why 8 packages are still behind

## The incident (v1.1.0, 2026-07-28)

`da0e49eb` ("migrate Living Time providers to @riverpod codegen") re-resolved
`pubspec.lock` as a side effect. Nine packages moved **backwards**. One was
`sqlite3`, 3.2.0 → 2.9.4.

`sqlite3` 3.x bundles the native SQLite library itself. 2.x does not — it
delegates to `sqlite3_flutter_libs`, which was pinned at `0.6.0+eol`, a
tombstone release whose source reads *"This package does not do anything"*.
The pairing produced a Linux build **with no database engine in it at all**.

It reached users because nothing failed: the build succeeded, the full suite
passed, and macOS and Windows silently fell back to `/usr/lib/libsqlite3.dylib`
and `winsqlite3.dll`. The maintainer's only test machine is a Mac, so the
regression was **structurally invisible**. Fixed in v1.1.1.

## What guards it now

`dependency_floor_test.dart` — pure Dart, no native deps, so it fails on every
platform including the Mac where the bug could never reproduce:

1. **Floor check** — `dependency_floors.json` records all resolved packages.
   Nothing may fall below it. Upgrades pass.
2. **Disappearance check** — a package vanishing is as dangerous as a downgrade.
3. **SQLite pairing invariant** — the rule a version floor cannot express:
   `sqlite3` 3.x ⇒ flutter_libs 0.6.x (self-bundling);
   `sqlite3` 2.x ⇒ flutter_libs 0.5.x (plugin bundles it);
   **2.x + 0.6.x ⇒ no SQLite at all.**

Plus a build-artifact guard in all three Linux release workflows that fails the
job if no library in the bundle exports the SQLite C API.

**If a test here fails, do not regenerate the baseline to make it pass.**
Find out why the resolver moved backwards first.

## RESOLVED (2026-07-28): the 8 downgrades are restored

The dependency debt this file used to describe **no longer exists**. It was
cleared by bumping the CI Flutter pin from 3.41.1 to **3.44.8** (Dart 3.12.2)
and raising the constraints in the same change. The reasoning is kept because
it is what stops this recurring.

Final state after the Flutter **3.47.0** pin + 2026-08-20 dep refresh:
`analyzer` **13.3.0**, `drift` **2.34.3**, `drift_dev` **2.34.5**,
`sqlite3` **3.5.2** (self-bundling), `sqlite3_flutter_libs` **0.6.0+eol**,
`flutter_riverpod` **3.4.2**, `riverpod_generator` **4.0.8**,
`riverpod_annotation` **4.0.6**. Riverpod codegen was kept.

### Flutter 3.47.0 pin (2026-08-16) — Riverpod 3.4 lifted 2026-08-20

The CI pin is **3.47.0** (Dart 3.13.0). What the 3.47 worktree probe said
would resolve, now does:

- `riverpod_generator` **4.0.8** + `drift_dev` **2.34.5** + `analyzer` **13.3**
- `file_picker` **≥12.1.1** compiles via `picker_prefs` (`FilePickerResult` shim, `pickFile()` for single picks). Not 12.0.0 (flags not forwarded) and not 12.1.0 (`skipEntitlementsChecks` is a no-op).
- `package_info_plus` 10 / `win32` 6 ride file_picker 12. Landed together.
- Syncfusion 34 / `xml` 7 still blocked by `webdav_client` 1.2.2.
  (`image` 4.9.2 resolved on xml 6 — the 4.9/xml-7 block is gone.)

### Still blocked (do not force)

| Package | Blocker |
|---------|---------|
| `syncfusion_flutter_pdf` ≥34 | needs `xml` ^7; `webdav_client` 1.2.2 needs `xml` ^6 |
| ~~`flutter_markdown`~~ | **migrated** to `flutter_markdown_plus` (2026-07-28) |

Majors that **did** land: `file_picker` 12.1.1, `package_info_plus` 10, `record` 7, `grpc` 5, `flat_buffers` 25, `shelf_web_socket` 3.

### Why it was unsolvable before

Flutter 3.41.1's `flutter_test` pinned `meta` to exactly 1.17.0, capping
`analyzer` at 10.0.1. `drift_dev` 2.32.0 needs `analyzer ^10.0.0` and would
have fitted — but **`riverpod_generator` skipped analyzer 10 and 11 entirely**
(`^9.0.0` at 4.0.3, then straight to `^12.0.0` at 4.0.4). No release accepted
the one analyzer version drift could use, so drift 2.32+ and Riverpod codegen
were mutually exclusive. That is exactly why the resolver downgraded drift when
codegen was introduced: it had no other move.

### Four traps, all found by doing rather than reasoning

1. **Bumping Flutter alone is a silent no-op.** Pub keeps the existing lock
   wherever it is still valid, so `pub get` on the new SDK changes nothing.
   The constraints in `pubspec.yaml` must rise in the same change.
2. **`riverpod_generator` 4.0.7 does not work even on 3.44.8.** It pulls
   `riverpod_annotation` 4.0.5 → `riverpod` 3.4.1 → `test`, which needs a
   `test_api` the SDK's `flutter_test` does not pin. **4.0.4 is the working
   version** (`analyzer ^12`), which `drift_dev` 2.34.0 accepts.
3. **`build_runner` can silently write zero outputs**, because its cache still
   considers reverted files current. Clear `.dart_tool/build` to force a real
   regeneration.
4. **The nightly broke afterwards, and no Rawhide-only change could fix it.**
   Scheduled workflows run the workflow FILE from the default branch while the
   nightly job checks out `ref: Rawhide`. So **main's `nightly.yml` Flutter pin
   must track Rawhide's**, not main's. See the comment on that pin.

### What the bump surfaced — a real bug, not a regression

Flutter 3.44 added a debug assertion, *"ListTile background color or ink
splashes may be invisible"*, which failed 5 goldens. It was **not** a rendering
artifact: `ExpansionTile` builds an internal `ListTile`, which paints its ink
onto the nearest Material ancestor, and two widgets wrapped one in a coloured
`Container` — swallowing the ripple. Those headers had been visually dead for
as long as they existed. Fixed in `creator_section_card.dart` and
`edit_character_page.dart` using `Material` + `RoundedRectangleBorder`.

Worth remembering at the next golden review: that fix produced an **8.99% pixel
diff** which, on inspection, was a **1px vertical shift** (`ShapeBorder` insets
differently than `BoxDecoration`) lighting up every text edge. A large diff
number is not automatically layout breakage — look before regenerating, and
look before rejecting.

### Verified end to end

Goldens **94/94** at CI parity (`--concurrency=1`); non-golden suite **2,591**;
`flutter analyze` 5 pre-existing `info`s and no new issues; the Linux release
built a working executable with `lib/libsqlite3.so` present; the nightly
published from Rawhide; CI green on Rawhide; and the maintainer confirmed **the
database and the app work on macOS** — the platform that switched from the
plugin to native assets, and the one no automated test could cover.
