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
}
