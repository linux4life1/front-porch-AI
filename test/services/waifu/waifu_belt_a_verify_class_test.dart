// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Belt A verify class: no argv[1] verb theater. Receipt and Build
// ask share one function + the same WaifuVerifyContext.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

WaifuToolResult _writeOk(String path) => WaifuToolResult(
  ok: true,
  output: 'wrote $path',
  write: WaifuWriteRecord(relativePath: path, before: 'old', after: 'new'),
);

WaifuTurnContract _afterWrites(Iterable<String> paths) {
  final turn = WaifuTurnContract.start('fix the files', null);
  for (final path in paths) {
    turn.noteResult(
      kWaifuToolWrite,
      _writeOk(path),
      _writeOk(path).write,
      args: {'path': path, 'contents': 'new'},
    );
  }
  return turn;
}

void _bash(WaifuTurnContract turn, String command, {bool ok = true}) {
  turn.noteResult(
    kWaifuToolBash,
    WaifuToolResult(ok: ok, output: ok ? 'passed' : 'failed'),
    null,
    args: {'command': command},
  );
}

void main() {
  test('argv[1] test is not verify: rm/grep/sed/git/wc', () {
    expect(waifuLooksVerifyCommand('rm test'), isFalse);
    expect(waifuLooksVerifyCommand('grep test README.md'), isFalse);
    expect(waifuLooksVerifyCommand('sed test'), isFalse);
    expect(waifuLooksVerifyCommand('git test'), isFalse);
    expect(waifuLooksVerifyCommand('wc test'), isFalse);
    const namedRm = WaifuVerifyContext(named: ['rm test']);
    expect(waifuLooksVerifyCommand('rm test', context: namedRm), isFalse);
    expect(waifuNamedVerifyCommands('then `rm test` the leftover'), isEmpty);
  });

  test('rm test mutates and Build needsAsk; cannot stamp tested', () {
    expect(waifuBashMutates('rm test'), isTrue);
    expect(
      WaifuPermissions(
        mode: WaifuMode.build,
      ).needsAsk(name: 'bash', args: {'command': 'rm test'}),
      isTrue,
    );
    final turn = _afterWrites(['mod.py']);
    _bash(turn, 'rm test');
    expect(turn.tested, isFalse);
  });

  test('tox -e py: named/stepVerify receipt and no-ask agree', () {
    const tox = WaifuVerifyContext(
      stepVerify: ['tox -e py'],
      named: ['tox -e py'],
    );
    expect(waifuLooksVerifyCommand('tox -e py', context: tox), isTrue);
    expect(waifuLooksVerifyCommand('tox -e py'), isFalse);
    expect(waifuBashMutates('tox -e py', context: tox), isFalse);
    expect(waifuBashMutates('tox -e py'), isTrue);
    expect(
      (WaifuPermissions(mode: WaifuMode.build)..verifyContext = tox).needsAsk(
        name: 'bash',
        args: {'command': 'tox -e py'},
      ),
      isFalse,
    );
    expect(
      WaifuPermissions(
        mode: WaifuMode.build,
      ).needsAsk(name: 'bash', args: {'command': 'tox -e py'}),
      isTrue,
    );
    final receipt = _afterWrites(['mod.py'])..verifyContext = tox;
    _bash(receipt, 'tox -e py');
    expect(receipt.tested, isTrue);
  });

  test('poetry / bundle wrappers: receipt and no-ask agree', () {
    expect(waifuLooksVerifyCommand('poetry run pytest'), isTrue);
    expect(waifuLooksVerifyCommand('bundle exec rspec'), isTrue);
    expect(waifuBashMutates('poetry run pytest'), isFalse);
    expect(waifuBashMutates('bundle exec rspec'), isFalse);
    final p = WaifuPermissions(mode: WaifuMode.build);
    expect(
      p.needsAsk(name: 'bash', args: {'command': 'poetry run pytest'}),
      isFalse,
    );
    expect(
      p.needsAsk(name: 'bash', args: {'command': 'bundle exec rspec'}),
      isFalse,
    );
    final poetry = _afterWrites(['mod.py']);
    _bash(poetry, 'poetry run pytest');
    expect(poetry.tested, isTrue);
    final rspec = _afterWrites(['spec.rb']);
    _bash(rspec, 'bundle exec rspec');
    expect(rspec.tested, isTrue);
  });

  test('tsc --noEmit and cmake --target test are verify-shaped', () {
    expect(waifuLooksVerifyCommand('tsc --noEmit'), isTrue);
    expect(waifuLooksVerifyCommand('tsc --no-emit'), isTrue);
    expect(waifuLooksVerifyCommand('tsc'), isFalse);
    expect(waifuLooksVerifyCommand('cmake --build . --target test'), isTrue);
    expect(waifuLooksVerifyCommand('cmake --build . -t tests'), isTrue);
    expect(waifuLooksVerifyCommand('cmake --build .'), isFalse);
    expect(waifuBashMutates('tsc --noEmit'), isFalse);
    expect(waifuBashMutates('cmake --build . --target test'), isFalse);
    final tsc = _afterWrites(['main.ts']);
    _bash(tsc, 'tsc --noEmit');
    expect(tsc.tested, isTrue);
  });

  test('gradlew/mvnw wrappers are gradle/mvn for ask and tested', () {
    const wrappers = [
      './gradlew test',
      'gradlew test',
      './mvnw test',
      'mvnw test',
    ];
    const gradleMarker = WaifuVerifyContext(markers: ['gradle test']);
    const mvnMarker = WaifuVerifyContext(markers: ['mvn test']);
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in wrappers) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(
      waifuLooksVerifyCommand('./gradlew test', context: gradleMarker),
      isTrue,
    );
    const gradleNamed = WaifuVerifyContext(
      named: ['gradle test'],
      stepVerify: ['gradle test'],
    );
    expect(
      waifuLooksVerifyCommand('./gradlew test', context: gradleNamed),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('./mvnw test', context: mvnMarker), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew build'), isFalse);
    expect(waifuLooksVerifyCommand('./mvnw package'), isFalse);
    expect(waifuLooksVerifyCommand('rm test'), isFalse);
    expect(waifuLooksVerifyCommand('grep test README.md'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('npm test'), isTrue);
    expect(waifuLooksVerifyCommand('pytest'), isTrue);
    expect(waifuLooksVerifyCommand('poetry run pytest'), isTrue);
    expect(waifuLooksVerifyCommand('bundle exec rspec'), isTrue);
  });

  test(
    'markers emit wrapper cue; named gradle test fulfills ./gradlew',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_wrap_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File(p.join(root.path, 'build.gradle')).writeAsString('');
      await File(p.join(root.path, 'gradlew')).writeAsString('');
      await File(p.join(root.path, 'Makefile')).writeAsString('');
      final markers = await waifuVerifyMarkerCommands(root.path);
      expect(markers, contains('./gradlew test'));
      expect(markers, contains('gradle test'));
      expect(markers, contains('make test'));
      final ctx = await waifuBuildVerifyContext(
        folderRoot: root.path,
        task: 'run `gradle test`',
      );
      expect(ctx.named, contains('gradle test'));
      expect(waifuLooksVerifyCommand('./gradlew test', context: ctx), isTrue);
    },
  );

  test('make / ruff / JS exec are verify-shaped; theater stays false', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'make test',
      'make check',
      'make lint',
      'ruff check .',
      'yarn exec jest',
      'npm exec jest',
      'pnpm exec jest',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.c']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('make build'), isFalse);
    expect(waifuLooksVerifyCommand('ruff format'), isFalse);
    expect(waifuLooksVerifyCommand('rm test'), isFalse);
    expect(waifuLooksVerifyCommand('grep test README.md'), isFalse);
    expect(waifuBashMutates('rm test'), isTrue);
    expect(p.needsAsk(name: 'bash', args: {'command': 'rm test'}), isTrue);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('npm test'), isTrue);
    expect(waifuLooksVerifyCommand('pytest'), isTrue);
    expect(waifuLooksVerifyCommand('poetry run pytest'), isTrue);
    expect(waifuLooksVerifyCommand('bundle exec rspec'), isTrue);
    expect(waifuLooksVerifyCommand('tsc --noEmit'), isTrue);
    expect(waifuLooksVerifyCommand('cmake --build . --target test'), isTrue);
  });

  test('existing cargo/npm/pytest/flutter pins still pass', () {
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
    expect(waifuLooksVerifyCommand('npm test'), isTrue);
    expect(waifuLooksVerifyCommand('pytest'), isTrue);
    expect(waifuLooksVerifyCommand('flutter test'), isTrue);
    expect(waifuLooksVerifyCommand('dart analyze'), isTrue);
    final p = WaifuPermissions(mode: WaifuMode.build);
    expect(p.needsAsk(name: 'bash', args: {'command': 'cargo test'}), isFalse);
    expect(p.needsAsk(name: 'bash', args: {'command': 'npm test'}), isFalse);
    expect(p.needsAsk(name: 'bash', args: {'command': 'pytest'}), isFalse);
    expect(
      p.needsAsk(name: 'bash', args: {'command': 'flutter test'}),
      isFalse,
    );
  });

  test('flags and qualified tasks still receipt; theater stays false', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    const makeHint = WaifuVerifyContext(
      named: ['make test'],
      stepVerify: ['make test'],
    );
    for (final cmd in [
      'make -j8 test',
      'make -j 8 test',
      r'make -j$(nproc) test',
      'make -C build test',
      './gradlew :app:test',
      './gradlew testDebugUnitTest',
      './gradlew check',
      'gradle check',
      'mvn verify',
      './mvnw verify',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('make -j8 test', context: makeHint), isTrue);
    expect(waifuLooksVerifyCommand('rm test'), isFalse);
    expect(waifuLooksVerifyCommand('grep test README.md'), isFalse);
    expect(waifuLooksVerifyCommand('make build'), isFalse);
    expect(waifuLooksVerifyCommand('ruff format'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew build'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew package'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew assemble'), isFalse);
    expect(waifuBashMutates('rm test'), isTrue);
    expect(p.needsAsk(name: 'bash', args: {'command': 'rm test'}), isTrue);
  });

  test('subcommand-first later test/clippy is not verify', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo new test',
      'cargo install clippy',
      'go get test',
      'dotnet new test',
      'dart create test',
      'mix new test',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.rs']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    const cargoHint = WaifuVerifyContext(named: ['cargo test']);
    expect(
      waifuLooksVerifyCommand('cargo new test', context: cargoHint),
      isFalse,
    );
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
    expect(waifuLooksVerifyCommand('cargo --locked test'), isTrue);
    expect(waifuLooksVerifyCommand('go test'), isTrue);
    expect(waifuLooksVerifyCommand('make -j8 test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew :app:test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn verify'), isTrue);
  });

  test('echo / ls / help / dry-run / build-without-test still fail', () {
    expect(waifuLooksVerifyCommand('echo cargo test'), isFalse);
    expect(waifuLooksVerifyCommand('ls -la'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test --help'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test --dry-run'), isFalse);
    expect(waifuLooksVerifyCommand('tsc --noEmit --help'), isFalse);
    expect(waifuLooksVerifyCommand('cargo build'), isFalse);
    expect(waifuLooksVerifyCommand('npm run build'), isFalse);
    expect(waifuLooksVerifyCommand('swift build'), isFalse);
  });
}
