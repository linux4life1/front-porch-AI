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

  test('dry-run / help / inventory do not receipt a check', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'make -n test',
      'make -n -C build test',
      'make test -n',
      'make --just-print test',
      'make --recon test',
      './gradlew test -m',
      './gradlew -m test',
      './gradlew :app:test -m',
      './gradlew help --task test',
      './gradlew dependencies --configuration test',
      'ctest -N',
      'ctest --show-only',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('make -j8 test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew :app:test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn verify'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo new test'), isFalse);
    expect(waifuLooksVerifyCommand('pytest -n auto'), isTrue);
  });

  test('cargo +channel is the toolchain, not the subcommand', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo +nightly test',
      'cargo +stable clippy',
      'cargo +nightly --locked test',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.rs']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('cargo new test'), isFalse);
    expect(waifuBashMutates('cargo new test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
  });

  test('Gradle inventory basename and --configuration/--task are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      './gradlew :app:dependencies --configuration test',
      './gradlew app:dependencies --configuration test',
      './gradlew :app:help --task test',
      './gradlew components --configuration test',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('ctest --show-only=b'), isFalse);
    expect(waifuLooksVerifyCommand('pytest --collect-only'), isFalse);
    expect(waifuLooksVerifyCommand('jest --listTests'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('make -j8 test'), isTrue);
    expect(
      waifuLooksVerifyCommand('./gradlew test --configuration-cache'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('./gradlew :app:test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn verify'), isTrue);
    expect(waifuLooksVerifyCommand('pytest -n auto'), isTrue);
    expect(waifuLooksVerifyCommand('make -n test'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew test -m'), isFalse);
    expect(waifuLooksVerifyCommand('ctest -N'), isFalse);
  });

  test('compile or list without execute is not a check', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo test --no-run',
      'cargo +nightly test --no-run',
      'cargo test --no-run --quiet',
      'go test -c',
      'dotnet test --list-tests',
      'phpunit --list-tests',
      'make -q test',
      'make --question test',
      'pytest --co',
      'jest --listTestFiles',
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
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo +nightly test'), isTrue);
    expect(waifuLooksVerifyCommand('make -j8 test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew :app:test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn verify'), isTrue);
    expect(waifuLooksVerifyCommand('pytest -n auto'), isTrue);
    expect(waifuLooksVerifyCommand('cargo new test'), isFalse);
    expect(waifuLooksVerifyCommand('make -n test'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew test -m'), isFalse);
    expect(
      waifuLooksVerifyCommand(
        './gradlew :app:dependencies --configuration test',
      ),
      isFalse,
    );
    expect(waifuLooksVerifyCommand('ctest -N'), isFalse);
    expect(waifuLooksVerifyCommand('pytest --collect-only'), isFalse);
  });

  test('skip or exclude a check is not verify', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'mvn test -DskipTests',
      'mvn -DskipTests test',
      'mvn verify -DskipTests',
      'mvn test -Dmaven.test.skip=true',
      './gradlew build -x test',
      './gradlew assemble -x test',
      './gradlew check -x test',
      './gradlew test -x test',
      './gradlew :app:test -x test',
      './gradlew build -x testDebugUnitTest',
      './gradlew --exclude-task test',
      './gradlew test --exclude-task test',
      './gradlew build --exclude-task=:app:test',
      'go test -exec true',
      'phpunit --list-suites',
      'phpunit --list-groups',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('mvn test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn verify'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -DskipTests=false'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew :app:test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew check'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test -x lint'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test --no-run'), isFalse);
    expect(waifuLooksVerifyCommand('make -n test'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew test -m'), isFalse);
    expect(
      waifuLooksVerifyCommand(
        './gradlew :app:dependencies --configuration test',
      ),
      isFalse,
    );
    expect(waifuLooksVerifyCommand('cargo new test'), isFalse);
  });

  test('surefire skip and glob exclude are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'mvn test -Dsurefire.skip=true',
      'mvn test -Dsurefire.skipExec=true',
      'mvn test -Dmaven.test.skip.exec=true',
      "./gradlew test -x '*Test*'",
      './gradlew test -x *Test*',
      "./gradlew test --exclude-task '*Test*'",
      './gradlew test --exclude-task=*check*',
      'mvn test -Dtest=None',
      './gradlew test --tests none.Matching',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('mvn test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test -x lint'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -DskipTests=false'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -Dsurefire.skip=false'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -DskipITs'), isTrue);
    expect(waifuLooksVerifyCommand("./gradlew test -x '*contest*'"), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -DskipTests'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew build -x test'), isFalse);
  });

  test('exclude glob matches Tests and UnitTest shapes', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      "./gradlew test -x '*Tests*'",
      './gradlew test -x *Tests*',
      './gradlew test -x *Tests',
      './gradlew :app:test -x "*Tests*"',
      "./gradlew test -x '*UnitTest*'",
      './gradlew test -x *UnitTest*',
      'mvn test -Dtest=DoesNotExist',
      'mvn test -Dtest=',
      './gradlew test --tests DoesNotExist',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('./gradlew test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test -x lint'), isTrue);
    expect(waifuLooksVerifyCommand("./gradlew test -x '*contest*'"), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -DskipITs'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -Dsurefire.skip=false'), isTrue);
    expect(waifuLooksVerifyCommand("./gradlew test -x '*Test*'"), isFalse);
  });

  test('failsafe skip is IT-only; explicit test filters are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'mvn verify -Dfailsafe.skip=true',
      'mvn verify -Dfailsafe.skipExec=true',
      'mvn verify -DskipITs',
      'mvn test -Dfailsafe.skip=true',
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
    for (final cmd in [
      'mvn test -Dtest=Nope',
      './gradlew test --tests Nope',
      './gradlew test --tests=',
      'mvn test -DfailIfNoTests=false -Dtest=Nope',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('./gradlew test --tests *'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --tests=*'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -DskipTests'), isFalse);
    expect(waifuLooksVerifyCommand('mvn test -Dsurefire.skip=true'), isFalse);
    expect(waifuLooksVerifyCommand("./gradlew test -x '*Tests*'"), isFalse);
  });

  test('polyglot name/path filters are theater; full suites still run', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'go test -run Nope',
      'cargo test nope',
      'cargo test -- --exact nope',
      'pytest -k nope',
      'pytest tests/test_foo.py',
      'dotnet test --filter FullyQualifiedName~Nope',
      'flutter test test/foo_test.dart',
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
    for (final cmd in [
      'go test',
      'go test ./...',
      'cargo test',
      'pytest',
      'dotnet test',
      'flutter test',
      'mvn test',
      './gradlew test',
      './gradlew test --tests *',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.rs']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('mvn test -Dfailsafe.skip=true'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -Dtest=Nope'), isFalse);
    expect(waifuLooksVerifyCommand('./gradlew test --tests Nope'), isFalse);
    expect(waifuLooksVerifyCommand('pytest -n auto'), isTrue);
  });

  test('flutter/dart --name and tags filters are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'flutter test --name Foo',
      'dart test --name Foo',
      'flutter test --plain-name Foo',
      'flutter test --tags golden',
      'dart test --exclude-tags golden',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.dart']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('flutter test'), isTrue);
    expect(waifuLooksVerifyCommand('dart test'), isTrue);
    expect(waifuLooksVerifyCommand('flutter test test/foo_test.dart'), isFalse);
    expect(waifuLooksVerifyCommand('go test -run Nope'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
  });

  test('value-flag, package, and adjacent runner filters are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'pytest -m nope',
      'flutter test --name Foo',
      'flutter test --plain-name Foo',
      'flutter test --tags golden',
      'flutter test --exclude-tags golden',
      'dart test --name Foo',
      'go test ./pkg',
      'go test ./internal/...',
      'cargo test -p foo',
      'cargo test --test integ',
      'jest -t',
      'npx jest -t',
      'vitest -t',
      'npm test -- -t',
      'mix test test/foo_test.exs',
      'zig test src/foo.zig',
      'swift test --filter',
      'rspec spec/foo_spec.rb',
      'phpunit tests/FooTest.php',
      'deno test test/foo_test.ts',
      'bun test test/foo.test.ts',
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
    for (final cmd in [
      'go test',
      'go test ./...',
      'cargo test',
      'pytest',
      'dotnet test',
      'flutter test',
      'dart test',
      'mvn test',
      './gradlew test',
      './gradlew test --tests *',
      'pytest -n auto',
      'mvn verify -Dfailsafe.skip=true',
      'zig build test',
      'swift test',
      'mix test',
      'bun test',
      'jest',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.rs']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('go test -run Nope'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test nope'), isFalse);
    expect(waifuLooksVerifyCommand('pytest -k nope'), isFalse);
    expect(waifuLooksVerifyCommand('flutter test test/foo_test.dart'), isFalse);
  });

  test(
    'cargo test targets and zig test-filter are theater; clippy -p is not',
    () {
      final p = WaifuPermissions(mode: WaifuMode.build);
      for (final cmd in [
        'cargo test --lib',
        'cargo test --bin foo',
        'cargo test --bin',
        'cargo test --example foo',
        'cargo test --doc',
        'zig build test -Dtest-filter=foo',
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
      for (final cmd in [
        'cargo test',
        'cargo clippy',
        'cargo clippy -p foo',
        'zig build test',
        'zig test',
      ]) {
        expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
        expect(waifuBashMutates(cmd), isFalse, reason: cmd);
        expect(
          p.needsAsk(name: 'bash', args: {'command': cmd}),
          isFalse,
          reason: cmd,
        );
        final turn = _afterWrites(['mod.rs']);
        _bash(turn, cmd);
        expect(turn.tested, isTrue, reason: cmd);
      }
      expect(waifuLooksVerifyCommand('cargo test -p foo'), isFalse);
      expect(waifuLooksVerifyCommand('cargo test --test integ'), isFalse);
      expect(waifuLooksVerifyCommand('jest -t'), isFalse);
      expect(waifuLooksVerifyCommand('go test ./pkg'), isFalse);
    },
  );

  test('cargo test target sets and zig --test-filter are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo test --bench',
      'cargo test --bench foo',
      'cargo test --bins',
      'cargo test --benches',
      'cargo test --examples',
      'cargo test --tests',
      'cargo test --all-targets',
      'cargo test --workspace',
      'zig build test --test-filter foo',
      'zig test -Dtest-filter=noop',
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
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
    expect(waifuLooksVerifyCommand('zig build test'), isTrue);
    expect(waifuLooksVerifyCommand('zig test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test --lib'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -p foo'), isFalse);
    expect(
      waifuLooksVerifyCommand('zig build test -Dtest-filter=foo'),
      isFalse,
    );
  });

  test('clippy subsets and cargo test --exclude/--all are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo clippy --lib',
      'cargo clippy --bin foo',
      'cargo clippy --bin',
      'cargo clippy --bins',
      'cargo clippy --tests',
      'cargo clippy --benches',
      'cargo clippy --examples',
      'cargo clippy --all-targets',
      'cargo test --exclude foo',
      'cargo test --all',
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
    for (final cmd in [
      'cargo test',
      'cargo clippy',
      'cargo clippy -p foo',
      'cargo clippy --workspace',
      'cargo clippy --all',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.rs']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('cargo test --lib'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test --bins'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test --workspace'), isFalse);
    expect(
      waifuLooksVerifyCommand('zig build test --test-filter foo'),
      isFalse,
    );
  });

  test(
    'clippy --exclude and --doc are theater even with workspace expanders',
    () {
      final p = WaifuPermissions(mode: WaifuMode.build);
      for (final cmd in [
        'cargo clippy --exclude foo',
        'cargo clippy --workspace --exclude foo',
        'cargo clippy --all --exclude bar',
        'cargo clippy -p foo --exclude bar',
        'cargo clippy --doc',
        'cargo clippy --workspace --doc',
        'cargo clippy --all --doc',
        'cargo clippy -p foo --doc',
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
      expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --workspace'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --all'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --lib'), isFalse);
      expect(waifuLooksVerifyCommand('cargo clippy --bins'), isFalse);
      expect(waifuLooksVerifyCommand('cargo test --exclude foo'), isFalse);
      expect(waifuLooksVerifyCommand('cargo test --all'), isFalse);
    },
  );

  test(
    'clippy feature and target gates are theater even with workspace expanders',
    () {
      final p = WaifuPermissions(mode: WaifuMode.build);
      for (final cmd in [
        'cargo clippy --workspace --no-default-features',
        'cargo clippy --all --features foo',
        'cargo clippy --workspace --target wasm32-unknown-unknown',
        'cargo clippy --no-default-features',
        'cargo clippy --features foo',
        'cargo clippy --features=foo',
        'cargo clippy --target wasm32-unknown-unknown',
        'cargo clippy --target=wasm32-unknown-unknown',
        'cargo clippy -p foo --features bar',
        'cargo clippy --all --no-default-features',
        'cargo clippy -p foo --no-default-features',
        'cargo clippy -p foo --target wasm32-unknown-unknown',
        'cargo clippy --workspace --features foo',
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
      expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --workspace'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --all'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --lib'), isFalse);
      expect(waifuLooksVerifyCommand('cargo clippy --exclude foo'), isFalse);
      expect(waifuLooksVerifyCommand('cargo clippy --doc'), isFalse);
      expect(waifuLooksVerifyCommand('cargo test --exclude foo'), isFalse);
      expect(waifuLooksVerifyCommand('cargo test --all'), isFalse);
    },
  );

  test(
    'clippy -F short features alias is theater even with workspace expanders',
    () {
      final p = WaifuPermissions(mode: WaifuMode.build);
      for (final cmd in [
        'cargo clippy -F foo',
        'cargo clippy --workspace -F foo',
        'cargo clippy -F=bar',
        'cargo clippy --all -F foo',
        'cargo clippy -p foo -F bar',
        'cargo clippy --features foo',
        'cargo clippy --features=foo',
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
      expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --workspace'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --all'), isTrue);
      expect(waifuLooksVerifyCommand('cargo clippy --lib'), isFalse);
      expect(waifuLooksVerifyCommand('cargo clippy --exclude foo'), isFalse);
      expect(waifuLooksVerifyCommand('cargo clippy --doc'), isFalse);
      expect(waifuLooksVerifyCommand('cargo test --exclude foo'), isFalse);
      expect(waifuLooksVerifyCommand('cargo test --all'), isFalse);
    },
  );

  test('clippy glued -FVALUE short features alias is theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo clippy -Ffoo',
      'cargo clippy -Fserde',
      'cargo clippy --workspace -Fserde',
      'cargo clippy --all -Ffoo',
      'cargo clippy -p foo -Fserde',
      'cargo clippy -F',
      'cargo clippy -F foo',
      'cargo clippy -F=bar',
      'cargo clippy --features foo',
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
    expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --workspace'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --all'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --all-features'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --lib'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy --features foo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy -F foo'), isFalse);
  });

  test('clippy and cargo-test presence flags do not VIP-star', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo clippy -F*',
      'cargo clippy -F=*',
      'cargo clippy --features *',
      'cargo clippy --features=*',
      'cargo clippy --workspace -F*',
      'cargo clippy --exclude *',
      'cargo clippy --exclude=*',
      'cargo clippy --target *',
      'cargo test -p*',
      'cargo test -p *',
      'cargo test --package *',
      'cargo clippy --all -F*',
      'cargo clippy -p foo -F*',
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
    expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --workspace'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --all'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --all-features'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --tests *'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy -Ffoo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy -F foo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy -F=bar'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy --exclude foo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -p foo'), isFalse);
  });

  test('cargo test feature/target gates and clippy -p * are theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo test --features foo',
      'cargo test --features=foo',
      'cargo test -Ffoo',
      'cargo test -F*',
      'cargo test --features *',
      'cargo test --no-default-features',
      'cargo test --target wasm32-unknown-unknown',
      'cargo test --target=wasm32-unknown-unknown',
      'cargo test --exclude *',
      'cargo clippy -p *',
      'cargo clippy -p=*',
      'cargo clippy --package *',
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
    expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --package foo'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --workspace'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --all'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy --all-features'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test --exclude *'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -p foo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy -Ffoo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy -F foo'), isFalse);
  });

  test('cargo test libtest harness after -- is theater', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo test -- --ignored',
      'cargo test -- --skip=foo',
      'cargo test -- --skip',
      'cargo test -- --list',
      'cargo test -- --exclude-should-panic',
      'cargo test -p foo -- --ignored',
      'cargo test -- --skip foo',
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
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy'), isTrue);
    expect(waifuLooksVerifyCommand('cargo clippy -p foo'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test --features foo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo clippy -p *'), isFalse);
  });

  test('cargo test libtest valued knobs after -- are a full run', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo test -- --test-threads 1',
      'cargo test -- --format pretty',
      'cargo test -- --shuffle-seed 42',
      'cargo test -- --logfile /tmp/t.log',
      'cargo test -- --test-threads=1',
      'cargo test -- --format=pretty',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.rs']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('cargo test -- --ignored'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -- --skip=foo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -- --skip'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -- --list'), isFalse);
    expect(
      waifuLooksVerifyCommand('cargo test -- --exclude-should-panic'),
      isFalse,
    );
    expect(waifuLooksVerifyCommand('cargo test -- --skip foo'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
  });

  test('cargo test * / --exact * are theater; fuller knobs still run', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'cargo test *',
      'cargo test -- *',
      'cargo test --exact *',
      'cargo test --exact=*',
      'cargo test -- --exact *',
      'cargo test -- --exact=*',
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
    for (final cmd in [
      'cargo test -- --include-ignored',
      'cargo test -- --nocapture',
      'cargo test -- --test-threads 1',
      'cargo test -- --format pretty',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isTrue, reason: cmd);
      expect(waifuBashMutates(cmd), isFalse, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isFalse,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.rs']);
      _bash(turn, cmd);
      expect(turn.tested, isTrue, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('cargo test -- --ignored'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -- --exact nope'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
  });

  test('zig --test-filter * is theater; go/JVM VIP and cargo pins hold', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'zig test --test-filter *',
      'zig test --test-filter=*',
      'zig build test --test-filter *',
      'zig build test -Dtest-filter=*',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['mod.zig']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('zig test'), isTrue);
    expect(waifuLooksVerifyCommand('zig build test'), isTrue);
    expect(waifuLooksVerifyCommand('go test -run=*'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --tests *'), isTrue);
    expect(waifuLooksVerifyCommand('cargo test *'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test -- --exact *'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
  });

  test('--filter * is theater except Go/JVM VIP keepers', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'swift test --filter *',
      'swift test --filter=*',
      'dotnet test --filter *',
      'dotnet test --filter=*',
      'phpunit --filter *',
      'phpunit --filter=*',
      'deno test --filter *',
      'deno test --filter=*',
      'bun test --filter *',
      'bun test --filter=*',
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
    expect(waifuLooksVerifyCommand('swift test'), isTrue);
    expect(waifuLooksVerifyCommand('dotnet test'), isTrue);
    expect(waifuLooksVerifyCommand('phpunit'), isTrue);
    expect(waifuLooksVerifyCommand('deno test'), isTrue);
    expect(waifuLooksVerifyCommand('bun test'), isTrue);
    expect(waifuLooksVerifyCommand('go test -run=*'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --tests *'), isTrue);
    expect(waifuLooksVerifyCommand('zig test --test-filter=*'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test *'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
  });

  test('every suite-filter key is presence except Go/JVM keepers', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'pytest -k=*',
      'pytest --keyword=*',
      'pytest -m=*',
      'flutter test --name=*',
      'flutter test --plain-name=*',
      'flutter test --tags=*',
      'flutter test --exclude-tags=*',
      'flutter test -t=*',
      'flutter test -x=*',
      'dart test --name=*',
      'dart test --plain-name=*',
      'dart test --tags=*',
      'dart test --exclude-tags=*',
      'dart test -t=*',
      'dart test -x=*',
      'jest -t=*',
      'jest --testNamePattern=*',
      'jest --testPathPattern=*',
      'vitest -t=*',
      'vitest --testNamePattern=*',
      'vitest --testPathPattern=*',
      'phpunit --testsuite=*',
      'rspec -e=*',
      'rspec --example=*',
      'npm test -t=*',
      'npm test --testNamePattern=*',
      'npm test --testPathPattern=*',
      'pnpm test -t=*',
      'pnpm test --testNamePattern=*',
      'pnpm test --testPathPattern=*',
      'yarn test -t=*',
      'yarn test --testNamePattern=*',
      'yarn test --testPathPattern=*',
      'bun test -t=*',
      'bun test --testNamePattern=*',
      'bun test --testPathPattern=*',
      'deno test -t=*',
      'swift test --filter=*',
      'dotnet test --filter=*',
      'phpunit --filter=*',
      'bun test --filter=*',
      'deno test --filter=*',
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
    expect(waifuLooksVerifyCommand('test -t=*'), isFalse);
    expect(waifuLooksVerifyCommand('test --testNamePattern=*'), isFalse);
    expect(waifuLooksVerifyCommand('test --testPathPattern=*'), isFalse);
    expect(waifuLooksVerifyCommand('go test -run=*'), isTrue);
    expect(waifuLooksVerifyCommand('go test -run=.*'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --tests *'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --tests=*'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -Dtest=*'), isFalse);
    expect(waifuLooksVerifyCommand('./mvnw test -Dtest=*'), isFalse);
    expect(waifuLooksVerifyCommand('pytest'), isTrue);
    expect(waifuLooksVerifyCommand('flutter test'), isTrue);
    expect(waifuLooksVerifyCommand('jest'), isTrue);
    expect(waifuLooksVerifyCommand('zig test --test-filter=*'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test *'), isFalse);
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
  });

  test('maven -Dtest=* is theater; Gradle/Go VIP keepers hold', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in ['mvn test -Dtest=*', './mvnw test -Dtest=*']) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('mvn test'), isTrue);
    expect(waifuLooksVerifyCommand('./mvnw test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --tests=*'), isTrue);
    expect(waifuLooksVerifyCommand('go test -run=*'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -Dtest=Nope'), isFalse);
    expect(waifuLooksVerifyCommand('mvn test -DskipTests'), isFalse);
  });

  test('surefire/failsafe name filters are theater; Gradle/Go VIP hold', () {
    final p = WaifuPermissions(mode: WaifuMode.build);
    for (final cmd in [
      'mvn test -Dgroups=*',
      'mvn test -DexcludedGroups=*',
      'mvn test -Dsurefire.includes=*',
      'mvn test -Dincludes=*',
      'mvn test -Dexcludes=*',
      'mvn test -Dsurefire.excludes=*',
      'mvn test -Dsurefire.groups=*',
      'mvn verify -Dit.test=*',
      'mvn verify -Dfailsafe.test=*',
      'mvn verify -Dfailsafe.groups=*',
      'mvn test -Dsurefire.excludedGroups=*',
      'mvn verify -Dfailsafe.excludedGroups=*',
      'mvn verify -Dfailsafe.includes=*',
      'mvn verify -Dfailsafe.excludes=*',
      'mvn test -Dsurefire.test=*',
      'mvn test -Dsurefire.includeJUnit5Engines=*',
      'mvn test -Dsurefire.excludeJUnit5Engines=*',
      'mvn verify -Dfailsafe.includeJUnit5Engines=*',
      'mvn verify -Dfailsafe.excludeJUnit5Engines=*',
      'mvn test -Dsurefire.includesFile=*',
      'mvn test -Dsurefire.excludesFile=*',
      'mvn verify -Dfailsafe.includesFile=*',
      'mvn verify -Dfailsafe.excludesFile=*',
      'mvn test -DincludesFile=*',
      'mvn test -DexcludesFile=*',
      'mvn test -DincludeJUnit5Engines=*',
      'mvn test -DexcludeJUnit5Engines=*',
      'mvn verify -DincludesFile=*',
      './mvnw test -DincludesFile=*',
      './mvnw test -Dgroups=*',
      './mvnw verify -Dit.test=*',
      'mvn test -DsuiteXmlFiles=*',
      'mvn test -DsuiteXmlFiles=testng.xml',
      'mvn test -Dsurefire.suiteXmlFiles=*',
      'mvn test -Dsurefire.suiteXmlFiles=testng.xml',
      'mvn verify -Dfailsafe.suiteXmlFiles=*',
      'mvn test -DsuiteXmlFile=testng.xml',
      'mvn test -DdependenciesToScan=*',
      'mvn test -Dsurefire.dependenciesToScan=*',
      'mvn verify -Dfailsafe.dependenciesToScan=*',
      'mvn test -DclasspathDependencyExcludes=*',
      'mvn test -Dsurefire.classpathDependencyExcludes=*',
      'mvn test -DclasspathDependencyIncludes=*',
      'mvn test -Dsurefire.classpathDependencyIncludes=*',
      'mvn verify -Dfailsafe.classpathDependencyExcludes=*',
      'mvn verify -Dfailsafe.classpathDependencyIncludes=*',
      'mvn test -Dmaven.test.dependency.excludes=*',
      'mvn test -DclasspathDependencyScopeExclude=*',
      'mvn test -DtestClassesDirectory=target/alt-test-classes',
      'mvn test -DtestSourceDirectory=src/alt/test/java',
      'mvn test -Dsurefire.testClassesDirectory=target/alt-test-classes',
      'mvn test -Dsurefire.testSourceDirectory=src/alt/test/java',
      'mvn verify -Dfailsafe.testClassesDirectory=target/alt-test-classes',
      'mvn verify -Dfailsafe.testSourceDirectory=src/alt/test/java',
      'mvn test -Dproject.build.testOutputDirectory=target/alt-test-classes',
      'mvn test -DtestClasspathElements=target/alt-test-classes',
      'mvn test -DadditionalClasspathElements=*',
      'mvn test -Dsurefire.additionalClasspathElements=*',
      'mvn verify -Dfailsafe.additionalClasspathElements=*',
      'mvn test -Dmaven.test.additionalClasspath=*',
      'mvn test -DgeneratedTestSourcesDirectory=target/alt-gen-test',
      'mvn test -Dproject.build.generatedTestSourcesDirectory=target/alt-gen-test',
      'mvn test -Dsurefire.generatedTestSourcesDirectory=target/alt-gen-test',
      'mvn verify -Dfailsafe.generatedTestSourcesDirectory=target/alt-gen-test',
      'mvn test -DclassesDirectory=target/alt-classes',
      'mvn test -Dsurefire.classesDirectory=target/alt-classes',
      'mvn verify -Dfailsafe.classesDirectory=target/alt-classes',
      'mvn test -Dproject.build.outputDirectory=target/alt-classes',
      'mvn -f other/pom.xml test',
      'mvn --file other/pom.xml test',
      './mvnw -f other/pom.xml test',
      'mvn test -Dproject.build.generatedSourcesDirectory=target/alt-gen',
      'mvn -fother/pom.xml test',
      'mvn --file=other/pom.xml test',
      'mvn --fileother/pom.xml test',
      'mvn test -pl :foo',
      'mvn test --projects foo',
      'mvn test -rf :foo',
      'mvn test --resume-from :foo',
      'mvn -N test',
      'mvn test --non-recursive',
      'mvn -s settings.xml test',
      'mvn --settings=ci.xml test',
      'mvn -gs settings.xml test',
      'mvn --global-settings=ci.xml test',
      'mvn -Pprod test',
      'mvn --activate-profiles prod test',
      'mvn -f other/module-pom.xml test',
      'mvn -f /workspace/module/pom.xml test',
      'mvn -f /repo/services/api/pom.xml test',
      'mvn -f C:/proj/module/pom.xml test',
      'mvn -f /home/user/proj/pom.xml test',
      'mvn -t toolchains.xml test',
      'mvn --toolchains=ci-toolchains.xml test',
      'mvn -gt toolchains.xml test',
      'mvn --global-toolchains=ci-toolchains.xml test',
      'mvn -f /home/runner/work/repo/module/pom.xml test',
      'mvn test -DtestFailureIgnore=true',
      'mvn test -Dmaven.test.failure.ignore=true',
      'mvn test -Dsurefire.testFailureIgnore=true',
      'mvn verify -Dfailsafe.testFailureIgnore=true',
      'mvn --fail-never test',
      'mvn -fn test',
      'mvn test -Dmaven.test.error.ignore=true',
      'mvn test -Dsurefire.testErrorIgnore=true',
      'mvn verify -Dfailsafe.testErrorIgnore=true',
      'mvn -f D:/a/repo/module/pom.xml test',
      'mvn -f D:/a/1/s/module/pom.xml test',
      './gradlew test --continue',
      'mvn test -Dbasedir=/other',
      'mvn test -Dproject.basedir=',
      'mvn test -Dbasedir',
      'mvn test -Dproject.basedir',
      './gradlew -p other test',
      './gradlew --project-dir other test',
      './gradlew -pother test',
      './gradlew --project-dir=other test',
      './gradlew test -p',
      './gradlew --project-dir= test',
      './gradlew -b other.gradle test',
      './gradlew --build-file other.gradle test',
      './gradlew --settings-file other.settings.gradle test',
      './gradlew -p= test',
      './gradlew -p=other test',
      './gradlew -b=other.gradle test',
      './gradlew -c other.settings.gradle test',
      './gradlew -cother.settings.gradle test',
      './gradlew -c=other.settings.gradle test',
      './gradlew --include-build other test',
      './gradlew --include-build=other test',
      './gradlew -b subdir/build.gradle test',
      './gradlew -b /workspace/module/build.gradle test',
      './gradlew -p /workspace test',
      './gradlew --init-script init.gradle test',
      './gradlew -I init.gradle test',
      './gradlew --init-script= test',
      './gradlew --init-script=init.gradle test',
      './gradlew -Iinit.gradle test',
      './gradlew test -Dorg.gradle.continue=true',
      './gradlew test -Dorg.gradle.continue',
      './gradlew test -Dorg.gradle.continue=',
      './gradlew -g /tmp/ghome test',
      './gradlew --gradle-user-home=/tmp/ghome test',
      './gradlew --gradle-user-home /tmp/ghome test',
      './gradlew -g/tmp/ghome test',
      './gradlew test -DignoreFailures=true',
      './gradlew test -Dtest.ignoreFailures=true',
      './gradlew test -PignoreFailures=true',
      './gradlew test -DignoreFailures',
      './gradlew test -DignoreFailures=',
      './gradlew test -DfailOnNoMatchingTests=false',
      './gradlew test -PfailOnNoMatchingTests=false',
      './gradlew test -DfailOnNoMatchingTests',
      './gradlew test -DfailOnNoMatchingTests=',
      './gradlew test -Dtest.single=Foo',
      './gradlew test -Dtest.single',
      './gradlew test -Dtest.single=',
      './gradlew test -DfailOnNoDiscoveredTests=false',
      './gradlew test -PfailOnNoDiscoveredTests=false',
      './gradlew test -DfailOnNoDiscoveredTests',
      './gradlew test -Dtest.include=Foo',
      './gradlew test -Dtest.exclude=Bar',
      './gradlew test -Dtest.include=',
      './gradlew test -Ptest.single=Foo',
      './gradlew test -Ptest.include=Foo',
      './gradlew test -Ptest.exclude=Bar',
      'cargo test --no-fail-fast',
      'jest --passWithNoTests',
      'npm test -- --passWithNoTests',
      'mvn -f /home/vsts/work/1/s/module/pom.xml test',
      'mvn test -Dmaven.multiModuleProjectDirectory=/other',
      'mvn test -Dsession.executionRootDirectory=/other',
      'mvn test -DfailIfNoTests=false',
      'mvn test -Dsurefire.failIfNoTests=false',
      'mvn verify -DfailIfNoTests=false',
      'mvn test -DfailIfNoSpecifiedTests=false',
      'mvn test -Dsurefire.failIfNoSpecifiedTests=false',
      'mvn verify -Dfailsafe.failIfNoTests=false',
      'mvn verify -Dfailsafe.failIfNoSpecifiedTests=false',
      'mvn test -DfailIfNoTests',
      'mvn test -DfailIfNoTests=',
      'make -i test',
      'make --ignore-errors test',
      'make -k test',
      'make --keep-going test',
      'make --ignore-errors= test',
      'make --keep-going=true test',
      'make -ik test',
      'make -ki test',
      'make -ni test',
      'make -in test',
      'make -ikj2 test',
      'make -ikj8 test',
      'make -kj2 test',
      'make -ks test',
      'make -sk test',
      'make -iks test',
      'make -si test',
      'make -jk test',
      'make -j2k test',
      'make -kr test',
      'make -kw test',
      'make -kB test',
      'make test TESTS=foo',
      'make check TESTS=test_foo',
      'make test TEST=foo',
      'make check TESTSUITEFLAGS=--verbose',
      'make -kl test',
      'make -lk test',
      'make -kt test',
      'make -kv test',
      'make test XFAIL_TESTS=foo',
      'make test CHECK_TESTS=foo',
      'make test TESTS_ENVIRONMENT=foo=1',
      'make test AM_TESTS_ENVIRONMENT=foo=1',
      'ctest -R Foo',
      'ctest --tests-regex Foo',
      'ctest --tests-regex=Foo',
      'ctest -E Foo',
      'ctest -L Foo',
      'ctest -I 1,3',
      'ctest --exclude-regex Foo',
      'ctest -RFoo',
      'ctest --label-regex Foo',
      'ctest --exclude-label Foo',
      'ctest --label-exclude Foo',
      'ctest --label-regex=Foo',
      'ctest --tests-from-file list.txt',
      'ctest --exclude-from-file list.txt',
      'ctest -FA Foo',
      'ctest -FI Foo',
      'ctest -FA=Foo',
      'ctest --fixture-exclude-any Foo',
      'ctest -FS Foo',
      'ctest -FC Foo',
      'ctest -FS=Foo',
      'ctest --fixture-exclude-setup Foo',
      'ctest --fixture-exclude-cleanup Foo',
      'ctest --no-tests=ignore',
      'ctest --no-tests',
      'ctest --no-tests=',
      'ctest --rerun-failed',
      'pytest --lf',
      'pytest --last-failed',
      'pytest --ff',
      'pytest --failed-first',
      'jest --onlyFailures',
      'jest -o',
      'jest --onlyChanged',
      'npm test -- --lf',
      'npm test -- --last-failed',
      'npm test -- --ff',
      'npm test -- --onlyFailures',
      'npm run test -- --lf',
      'npm run test -- --onlyFailures',
      'pnpm test -- --onlyFailures',
      'yarn test -- --onlyFailures',
      'yarn test --onlyFailures',
      'bun test --onlyFailures',
      'deno test --onlyFailures',
      'npm run test:unit -- --onlyFailures',
      'npm run test:ci -- --onlyFailures',
      'yarn run test:unit --onlyFailures',
      'pnpm run test:e2e -- --onlyChanged',
      'npm run test:unit -- -o',
      'jest --changedSince main',
      'jest --findRelatedTests src/a.js',
      'jest --lastCommit',
      'vitest --changed',
      'vitest --related',
      'vitest --onlyChanged',
      'mix test --failed',
      'mix test --stale',
      'mix test --only SomeTest',
      'mix test --only=slow',
      'mix test --exclude SomeTest',
      'mix test --exclude=integration',
      'go test -short',
      'go test -skip Foo',
      'go test -skip=Foo',
      'go test -list .',
      'go test -list=.',
      'go test -fuzz=FuzzFoo',
      'go test -fuzz FuzzFoo',
      'phpunit --group=slow',
      'phpunit --group slow',
      'phpunit --exclude-group=slow',
      'phpunit --exclude-group slow',
      'phpunit -g=slow',
      'phpunit -g slow',
      'phpunit --order-by=defects',
      'phpunit --order-by defects',
      'phpunit --covers=Foo',
      'phpunit --covers Foo',
      'swift test --skip Foo',
      'swift test --skip=Foo',
      'npm run test:unit -- -t Foo',
      'npm run test:unit -- --testNamePattern=Foo',
      'npm run test:ci -- --testPathPattern=src',
      'yarn run test:unit -- -t Foo',
      'rspec --only-failures',
      'rspec --next-failure',
      'rspec -n',
      'rspec --tag=slow',
      'rspec --tag slow',
      'rspec --tag=focus',
      'rspec --tag=~slow',
      'rspec -t=focus',
      'rspec -t focus',
      'jest --watch',
      'jest --watchAll',
      'jest --shard=1/3',
      'vitest --shard=1/3',
      'npm test -- --shard=1/2',
      'npm test -- --watch',
      'jest --selectProjects=unit',
      'vitest --project=unit',
      'npm test -- --selectProjects=unit',
      'pytest --sw',
      'pytest --stepwise',
      'pytest --looponfail',
      'pytest -f',
      'rspec --pattern=spec/models',
      'rspec --exclude-pattern=slow',
      'rspec -P=foo',
      'rspec -P foo',
      'rspec -P spec/models',
      'rspec -P spec/**/*_spec.rb',
      'rspec -Pfoo',
      'rspec -P',
      'rspec --example-matches=foo',
      'jest --testPathIgnorePatterns=e2e',
      'npm test -- --testPathIgnorePatterns=e2e',
      'vitest --ui',
      'vitest --dir=packages/foo',
      'jest --runTestsByPath=a.test.js',
      'dart test -p chrome',
      'flutter test -d chrome',
      'phpunit --uses=Foo',
      'phpunit --uses Foo',
      'flutter test --total-shards=3',
      'flutter test --shard-index=0',
      'dart test --total-shards=3 --shard-index=1',
      'jest --changedFilesWithAncestor',
      'jest --watch=true',
      'jest --watchAll=',
      'make test SUBDIRS=foo',
      './gradlew test -Dtest.failOnNoMatchingTests=false',
      './gradlew test -Dtest.failOnNoDiscoveredTests=false',
      './gradlew test -Ptest.failOnNoMatchingTests=false',
      './gradlew test -Ptest.failOnNoDiscoveredTests=false',
      './gradlew test -Dtest.failOnNoMatchingTests',
      './gradlew test -Dtest.failOnNoMatchingTests=',
      './gradlew test -Dtest.filter.commandLineIncludePatterns=',
      './gradlew test -Dtest.filter.commandLineExcludePatterns=',
      './gradlew test -Ptest.filter.commandLineIncludePatterns=Foo',
    ]) {
      expect(waifuLooksVerifyCommand(cmd), isFalse, reason: cmd);
      expect(waifuBashMutates(cmd), isTrue, reason: cmd);
      expect(
        p.needsAsk(name: 'bash', args: {'command': cmd}),
        isTrue,
        reason: cmd,
      );
      final turn = _afterWrites(['Src.java']);
      _bash(turn, cmd);
      expect(turn.tested, isFalse, reason: cmd);
    }
    expect(waifuLooksVerifyCommand('mvn test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn verify'), isTrue);
    expect(waifuLooksVerifyCommand('./mvnw test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn -fae test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn --fail-at-end test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn -ff test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn -f pom.xml test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn -f ./pom.xml test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn --file=pom.xml test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn --file=./pom.xml test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn -fpom.xml test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn -f /workspace/pom.xml test'), isTrue);
    expect(waifuLooksVerifyCommand('mvn -f C:/proj/pom.xml test'), isTrue);
    expect(
      waifuLooksVerifyCommand('mvn -f D:/a/repo/repo/pom.xml test'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('mvn -f D:/a/1/s/pom.xml test'), isTrue);
    expect(
      waifuLooksVerifyCommand('mvn -f /home/vsts/work/1/s/pom.xml test'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('./gradlew test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew -p . test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew -p ./ test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test --continuous'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test -Pfoo'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test -PenableFoo'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew test -Pfoo=bar'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew -b build.gradle test'), isTrue);
    expect(waifuLooksVerifyCommand('./gradlew -b ./build.gradle test'), isTrue);
    expect(
      waifuLooksVerifyCommand('./gradlew -b build.gradle.kts test'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew --build-file=build.gradle test'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew --settings-file settings.gradle test'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand(
        './gradlew --settings-file settings.gradle.kts test',
      ),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand(
        './gradlew --settings-file ./settings.gradle test',
      ),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew -b /workspace/build.gradle test'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand(
        './gradlew -b /home/runner/work/repo/repo/build.gradle test',
      ),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew -b D:/a/1/s/build.gradle test'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand(
        './gradlew --settings-file /home/vsts/work/1/s/settings.gradle test',
      ),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('./gradlew test -i'), isTrue);
    expect(
      waifuLooksVerifyCommand('./gradlew test -Dorg.gradle.continue=false'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew test -DignoreFailures=false'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew test -PignoreFailures=false'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew test -Dtest.ignoreFailures=false'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew test -DfailOnNoMatchingTests=true'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew test -PfailOnNoMatchingTests=true'),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('./gradlew test -DfailOnNoDiscoveredTests=true'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('cargo test'), isTrue);
    expect(waifuLooksVerifyCommand('npm test'), isTrue);
    expect(waifuLooksVerifyCommand('jest'), isTrue);
    expect(
      waifuLooksVerifyCommand(
        'mvn -f /home/runner/work/repo/repo/pom.xml test',
      ),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('mvn -f /github/workspace/pom.xml test'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('mvn -T 1C test'), isTrue);
    expect(
      waifuLooksVerifyCommand('mvn test -DtestFailureIgnore=false'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('mvn test -DfailIfNoTests=true'), isTrue);
    expect(waifuLooksVerifyCommand('make test'), isTrue);
    expect(waifuLooksVerifyCommand('make -I extras test'), isTrue);
    expect(waifuLooksVerifyCommand('make -j8 test'), isTrue);
    expect(waifuLooksVerifyCommand('make -C build test'), isTrue);
    expect(waifuLooksVerifyCommand('make -f Makefile test'), isTrue);
    expect(
      waifuLooksVerifyCommand('make -C/home/runner/work/repo/repo test'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('make -f./common.mk test'), isTrue);
    expect(waifuLooksVerifyCommand('make -W/tmp/new test'), isTrue);
    expect(waifuLooksVerifyCommand('make -Onone test'), isTrue);
    expect(waifuLooksVerifyCommand('make -Oline test'), isTrue);
    expect(waifuLooksVerifyCommand('make -fmakefile test'), isTrue);
    expect(waifuLooksVerifyCommand('make -Cbuild/link test'), isTrue);
    expect(waifuLooksVerifyCommand('make -ooutfile test'), isTrue);
    expect(waifuLooksVerifyCommand('make -Wquick test'), isTrue);
    expect(waifuLooksVerifyCommand('ctest'), isTrue);
    expect(waifuLooksVerifyCommand('ctest -j8'), isTrue);
    expect(waifuLooksVerifyCommand('ctest --output-on-failure'), isTrue);
    expect(waifuLooksVerifyCommand('ctest --no-tests=error'), isTrue);
    expect(waifuLooksVerifyCommand('pytest'), isTrue);
    expect(waifuLooksVerifyCommand('jest'), isTrue);
    expect(waifuLooksVerifyCommand('jest --watchAll=false'), isTrue);
    expect(waifuLooksVerifyCommand('jest --watch=false'), isTrue);
    expect(waifuLooksVerifyCommand('jest --watchAll=0'), isTrue);
    expect(waifuLooksVerifyCommand('npm test -- --watchAll=false'), isTrue);
    expect(waifuLooksVerifyCommand('npm run test -- --watchAll=false'), isTrue);
    expect(waifuLooksVerifyCommand('vitest --watch=false'), isTrue);
    expect(waifuLooksVerifyCommand('rspec'), isTrue);
    expect(waifuLooksVerifyCommand('rspec -p'), isTrue);
    expect(waifuLooksVerifyCommand('rspec -p 10'), isTrue);
    expect(waifuLooksVerifyCommand('npm test'), isTrue);
    expect(waifuLooksVerifyCommand('pnpm test'), isTrue);
    expect(waifuLooksVerifyCommand('yarn test'), isTrue);
    expect(waifuLooksVerifyCommand('bun test'), isTrue);
    expect(waifuLooksVerifyCommand('npm run test:unit'), isTrue);
    expect(waifuLooksVerifyCommand('vitest'), isTrue);
    expect(waifuLooksVerifyCommand('mix test'), isTrue);
    expect(waifuLooksVerifyCommand('go test'), isTrue);
    expect(waifuLooksVerifyCommand('phpunit'), isTrue);
    expect(waifuLooksVerifyCommand('swift test'), isTrue);
    expect(
      waifuLooksVerifyCommand(
        './gradlew test -Dtest.failOnNoMatchingTests=true',
      ),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand(
        './gradlew test -Ptest.failOnNoMatchingTests=true',
      ),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand(
        './gradlew test -Dtest.failOnNoDiscoveredTests=true',
      ),
      isTrue,
    );
    expect(
      waifuLooksVerifyCommand('mvn test -Dmaven.test.error.ignore=false'),
      isTrue,
    );
    expect(waifuLooksVerifyCommand('./gradlew test --tests=*'), isTrue);
    expect(waifuLooksVerifyCommand('go test -run=*'), isTrue);
    expect(waifuLooksVerifyCommand('mvn test -Dtest=*'), isFalse);
    expect(waifuLooksVerifyCommand('mvn test -Dgroups=Foo'), isFalse);
  });
}
