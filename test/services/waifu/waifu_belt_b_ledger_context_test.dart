// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';

void main() {
  WaifuMessage bash(String command) => WaifuMessage.tool(
    name: kWaifuToolBash,
    output: 'ok',
    ok: true,
    args: {'command': command},
  );

  test('B2: named check is as-run only with the turn context', () {
    const named = 'tox -e py';
    final folded = [bash(named), bash('ls')];
    final bare = waifuMachineLedger(
      folded: folded,
      context: const WaifuVerifyContext(),
    );
    expect(bare, isNot(contains(named)));
    expect(bare.split('verify as-run:').last, isNot(contains('ls')));

    final ledger = waifuMachineLedger(
      folded: folded,
      context: const WaifuVerifyContext(named: [named]),
    );
    final verifyBlock = ledger
        .split('verify as-run:')
        .last
        .split('plan:')
        .first;
    expect(verifyBlock, contains(named));
    expect(verifyBlock, isNot(contains('ls')));
  });

  test('B2: surefire skip and glob exclude stay out of as-run', () {
    final ledger = waifuMachineLedger(
      folded: [
        bash('cargo test'),
        bash('cargo test --lib'),
        bash('cargo test --bin foo'),
        bash('cargo test --doc'),
        bash('cargo test --bins'),
        bash('cargo test --workspace'),
        bash('cargo test --bench'),
        bash('cargo clippy -p foo'),
        bash('cargo clippy --package foo'),
        bash('cargo clippy --workspace'),
        bash('cargo clippy --lib'),
        bash('cargo clippy --bins'),
        bash('cargo clippy --exclude foo'),
        bash('cargo clippy --workspace --exclude foo'),
        bash('cargo clippy --doc'),
        bash('cargo clippy --workspace --doc'),
        bash('cargo clippy --workspace --no-default-features'),
        bash('cargo clippy --all --features foo'),
        bash('cargo clippy --workspace --target wasm32-unknown-unknown'),
        bash('cargo clippy -F foo'),
        bash('cargo clippy --workspace -F foo'),
        bash('cargo clippy -F=bar'),
        bash('cargo clippy -Ffoo'),
        bash('cargo clippy -Fserde'),
        bash('cargo clippy --workspace -Fserde'),
        bash('cargo clippy --all -Ffoo'),
        bash('cargo clippy -p foo -Fserde'),
        bash('cargo clippy -F*'),
        bash('cargo clippy -F=*'),
        bash('cargo clippy --features *'),
        bash('cargo clippy --features=*'),
        bash('cargo clippy --workspace -F*'),
        bash('cargo clippy --exclude *'),
        bash('cargo clippy --exclude=*'),
        bash('cargo clippy --target *'),
        bash('cargo test -p*'),
        bash('cargo test -p *'),
        bash('cargo test --package *'),
        bash('cargo clippy --all -F*'),
        bash('cargo clippy -p foo -F*'),
        bash('cargo test --features foo'),
        bash('cargo test --features=foo'),
        bash('cargo test -Ffoo'),
        bash('cargo test -F*'),
        bash('cargo test --features *'),
        bash('cargo test --no-default-features'),
        bash('cargo test --target wasm32-unknown-unknown'),
        bash('cargo test --target=wasm32-unknown-unknown'),
        bash('cargo test --exclude *'),
        bash('cargo clippy -p *'),
        bash('cargo clippy -p=*'),
        bash('cargo clippy --package *'),
        bash('cargo test -- --ignored'),
        bash('cargo test -- --skip=foo'),
        bash('cargo test -- --skip'),
        bash('cargo test -- --list'),
        bash('cargo test -- --exclude-should-panic'),
        bash('cargo test -p foo -- --ignored'),
        bash('cargo test -- --skip foo'),
        bash('cargo test -- --test-threads 1'),
        bash('cargo test -- --format pretty'),
        bash('cargo test -- --shuffle-seed 42'),
        bash('cargo test -- --logfile /tmp/t.log'),
        bash('cargo test -- --test-threads=1'),
        bash('cargo test -- --format=pretty'),
        bash('cargo test -- *'),
        bash('cargo test *'),
        bash('cargo test -- --exact *'),
        bash('cargo test -- --exact=*'),
        bash('cargo test --exact *'),
        bash('cargo test --exact=*'),
        bash('cargo test -- --exact nope'),
        bash('cargo test -- --include-ignored'),
        bash('cargo test -- --nocapture'),
        bash('./gradlew test --tests *'),
        bash('go test -run=*'),
        bash('swift test'),
        bash('dotnet test'),
        bash('phpunit'),
        bash('deno test'),
        bash('bun test'),
        bash('swift test --filter *'),
        bash('swift test --filter=*'),
        bash('dotnet test --filter *'),
        bash('dotnet test --filter=*'),
        bash('phpunit --filter *'),
        bash('phpunit --filter=*'),
        bash('deno test --filter *'),
        bash('deno test --filter=*'),
        bash('bun test --filter *'),
        bash('bun test --filter=*'),
        bash('cargo test --exclude foo'),
        bash('cargo test --all'),
        bash('zig build test'),
        bash('zig test'),
        bash('zig build test -Dtest-filter=foo'),
        bash('zig build test --test-filter foo'),
        bash('zig test -Dtest-filter=noop'),
        bash('zig test --test-filter *'),
        bash('zig test --test-filter=*'),
        bash('zig build test --test-filter *'),
        bash('zig build test -Dtest-filter=*'),
        bash('mvn verify -Dfailsafe.skip=true'),
        bash('mvn verify'),
        bash('mvn test'),
        bash('./mvnw test'),
        bash('mvn test -Dgroups=*'),
        bash('mvn test -DexcludedGroups=*'),
        bash('mvn test -Dsurefire.includes=*'),
        bash('mvn verify -Dit.test=*'),
        bash('./mvnw test -Dgroups=*'),
        bash('./mvnw verify -Dit.test=*'),
        bash('mvn test -DincludesFile=*'),
        bash('mvn test -DexcludesFile=*'),
        bash('mvn test -DincludeJUnit5Engines=*'),
        bash('mvn test -DexcludeJUnit5Engines=*'),
        bash('./mvnw test -DincludesFile=*'),
        bash('mvn test -DsuiteXmlFiles=*'),
        bash('mvn test -DsuiteXmlFiles=testng.xml'),
        bash('mvn test -Dsurefire.suiteXmlFiles=*'),
        bash('mvn verify -Dfailsafe.suiteXmlFiles=*'),
        bash('mvn test -DdependenciesToScan=*'),
        bash('mvn test -DclasspathDependencyExcludes=*'),
        bash('mvn test -DclasspathDependencyIncludes=*'),
        bash('mvn test -Dsurefire.classpathDependencyExcludes=*'),
        bash('mvn verify -Dfailsafe.classpathDependencyIncludes=*'),
        bash('mvn test -Dmaven.test.dependency.excludes=*'),
        bash('mvn test -DclasspathDependencyScopeExclude=*'),
        bash('mvn test -DtestClassesDirectory=target/alt-test-classes'),
        bash('mvn test -DtestSourceDirectory=src/alt/test/java'),
        bash(
          'mvn test -Dsurefire.testClassesDirectory=target/alt-test-classes',
        ),
        bash('mvn verify -Dfailsafe.testSourceDirectory=src/alt/test/java'),
        bash(
          'mvn test -Dproject.build.testOutputDirectory=target/alt-test-classes',
        ),
        bash('mvn test -DtestClasspathElements=target/alt-test-classes'),
        bash('mvn test -DadditionalClasspathElements=*'),
        bash('mvn test -Dsurefire.additionalClasspathElements=*'),
        bash('mvn test -DgeneratedTestSourcesDirectory=target/alt-gen-test'),
        bash('mvn test -DclassesDirectory=target/alt-classes'),
        bash('mvn test -Dproject.build.outputDirectory=target/alt-classes'),
        bash('mvn -f other/pom.xml test'),
        bash('mvn --file other/pom.xml test'),
        bash('mvn -fae test'),
        bash('mvn --fail-never test'),
        bash('mvn -fn test'),
        bash('mvn test -Dmaven.test.error.ignore=true'),
        bash('mvn -f pom.xml test'),
        bash('mvn -f /workspace/pom.xml test'),
        bash('mvn -f /home/runner/work/repo/repo/pom.xml test'),
        bash('mvn -f D:/a/repo/repo/pom.xml test'),
        bash('mvn -f D:/a/1/s/pom.xml test'),
        bash('mvn -f /home/vsts/work/1/s/pom.xml test'),
        bash('mvn test -DtestFailureIgnore=true'),
        bash('mvn -f /workspace/module/pom.xml test'),
        bash('mvn -f D:/a/repo/module/pom.xml test'),
        bash('mvn -f D:/a/1/s/module/pom.xml test'),
        bash('mvn -f /home/vsts/work/1/s/module/pom.xml test'),
        bash('./gradlew test --continue'),
        bash('./gradlew -p other test'),
        bash('./gradlew test -p'),
        bash('./gradlew -b other.gradle test'),
        bash('./gradlew -b build.gradle test'),
        bash('./gradlew -b /workspace/build.gradle test'),
        bash('./gradlew test -i'),
        bash('./gradlew --init-script init.gradle test'),
        bash('./gradlew -I init.gradle test'),
        bash('./gradlew test -Dorg.gradle.continue=true'),
        bash('./gradlew -g /tmp/ghome test'),
        bash('./gradlew --gradle-user-home /tmp/ghome test'),
        bash('./gradlew test -DignoreFailures=true'),
        bash('./gradlew test -PignoreFailures=true'),
        bash('./gradlew test -DfailOnNoMatchingTests=false'),
        bash('./gradlew test -Dtest.single=Foo'),
        bash('cargo test --no-fail-fast'),
        bash('jest --passWithNoTests'),
        bash('./gradlew test -Ptest.single=Foo'),
        bash('mvn test -DfailIfNoTests=false'),
        bash('make test'),
        bash('make -i test'),
        bash('make -ik test'),
        bash('make -j8 test'),
        bash('make -C/home/runner/work/repo/repo test'),
        bash('ctest'),
        bash('ctest --no-tests=error'),
        bash('make -ks test'),
        bash('make test TESTS=foo'),
        bash('ctest -R Foo'),
        bash('ctest --no-tests=ignore'),
        bash('pytest --lf'),
        bash('yarn test --onlyFailures'),
        bash('npm run test:unit -- -t Foo'),
        bash('go test -short'),
        bash('jest --watch'),
        bash('jest --watchAll=false'),
        bash('rspec -p 10'),
        bash('rspec -P foo'),
        bash('npm test -- --dir=src'),
        bash('dart test --platform=vm'),
        bash('dotnet test --project Foo.Tests.csproj'),
        bash('vitest --project foo'),
        bash('./gradlew test -Dtest.failOnNoMatchingTests=false'),
        bash('./gradlew test -Ptest.filter.commandLineIncludePatterns=Foo'),
        bash('./gradlew -b /workspace/module/build.gradle test'),
        bash('./gradlew -p /workspace test'),
        bash('./gradlew -p= test'),
        bash('./gradlew -c other.settings.gradle test'),
        bash('./gradlew --include-build other test'),
        bash('./gradlew test --continuous'),
        bash('./gradlew test -PenableFoo'),
        bash('mvn test -Dbasedir=/other'),
        bash('mvn test -Dbasedir'),
        bash('mvn test -Dmaven.multiModuleProjectDirectory=/other'),
        bash('mvn -t toolchains.xml test'),
        bash('mvn -T 1C test'),
        bash('mvn -s settings.xml test'),
        bash('mvn -Pprod test'),
        bash('mvn -fother/pom.xml test'),
        bash('mvn test -pl :foo'),
        bash('mvn -N test'),
        bash('mvn test -Dproject.build.generatedSourcesDirectory=*'),
        bash('./gradlew test --tests=*'),
        bash('pytest'),
        bash('flutter test'),
        bash('jest'),
        bash('mvn test -Dtest=*'),
        bash('./mvnw test -Dtest=*'),
        bash('pytest -k=*'),
        bash('flutter test --name=*'),
        bash('jest -t=*'),
        bash('mvn test -Dsurefire.skip=true'),
        bash('mvn test -Dtest=Nope'),
        bash('./gradlew test --tests Nope'),
        bash('go test -run Nope'),
        bash('cargo test nope'),
        bash('pytest -k nope'),
        bash('flutter test test/foo_test.dart'),
        bash('flutter test --name Foo'),
        bash('pytest -m nope'),
        bash('cargo test -p foo'),
        bash('go test ./pkg'),
        bash("./gradlew test -x '*Test*'"),
        bash("./gradlew test -x '*Tests*'"),
        bash("./gradlew test -x '*UnitTest*'"),
      ],
      context: const WaifuVerifyContext(),
    );
    final verifyBlock = ledger
        .split('verify as-run:')
        .last
        .split('plan:')
        .first;
    final verifyLines = verifyBlock
        .trim()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    expect(verifyLines, contains('cargo test'));
    expect(verifyLines, contains('cargo clippy -p foo'));
    expect(verifyLines, contains('cargo clippy --package foo'));
    expect(verifyLines, contains('cargo clippy --workspace'));
    expect(verifyLines, contains('zig build test'));
    expect(verifyLines, contains('zig test'));
    expect(verifyLines, contains('mvn verify -Dfailsafe.skip=true'));
    expect(verifyLines, contains('mvn verify'));
    expect(verifyLines, contains('mvn test'));
    expect(verifyLines, contains('./mvnw test'));
    expect(verifyLines, contains('mvn -fae test'));
    expect(verifyLines, contains('mvn -f pom.xml test'));
    expect(verifyLines, contains('mvn -f /workspace/pom.xml test'));
    expect(verifyBlock, contains('/home/runner/work/repo/repo/pom.xml'));
    expect(verifyBlock, contains('D:/a/repo/repo/pom.xml'));
    expect(verifyBlock, contains('D:/a/1/s/pom.xml'));
    expect(verifyBlock, contains('/home/vsts/work/1/s/pom.xml'));
    expect(verifyLines, contains('./gradlew test --continuous'));
    expect(verifyLines, contains('./gradlew test -PenableFoo'));
    expect(verifyLines, contains('./gradlew -b build.gradle test'));
    expect(verifyLines, contains('./gradlew -b /workspace/build.gradle test'));
    expect(verifyLines, contains('./gradlew test -i'));
    expect(verifyLines, contains('make test'));
    expect(verifyLines, contains('make -j8 test'));
    expect(verifyLines, contains('make -C/home/runner/work/repo/repo test'));
    expect(verifyLines, contains('ctest'));
    expect(verifyLines, contains('ctest --no-tests=error'));
    expect(verifyLines, contains('jest --watchAll=false'));
    expect(verifyLines, contains('rspec -p 10'));
    expect(verifyLines, contains('dart test --platform=vm'));
    expect(verifyLines, contains('dotnet test --project Foo.Tests.csproj'));
    expect(verifyLines, contains('mvn -T 1C test'));
    expect(verifyLines, contains('./gradlew test --tests *'));
    expect(verifyLines, contains('./gradlew test --tests=*'));
    expect(verifyLines, contains('go test -run=*'));
    expect(verifyLines, contains('pytest'));
    expect(verifyLines, contains('flutter test'));
    expect(verifyLines, contains('jest'));
    expect(verifyLines, contains('swift test'));
    expect(verifyLines, contains('dotnet test'));
    expect(verifyLines, contains('phpunit'));
    expect(verifyLines, contains('deno test'));
    expect(verifyLines, contains('bun test'));
    expect(verifyLines, contains('cargo test -- --test-threads 1'));
    expect(verifyLines, contains('cargo test -- --format pretty'));
    expect(verifyLines, contains('cargo test -- --shuffle-seed 42'));
    expect(verifyLines, contains('cargo test -- --logfile /tmp/t.log'));
    expect(verifyLines, contains('cargo test -- --test-threads=1'));
    expect(verifyLines, contains('cargo test -- --format=pretty'));
    expect(verifyLines, contains('cargo test -- --include-ignored'));
    expect(verifyLines, contains('cargo test -- --nocapture'));
    expect(verifyLines, isNot(contains('cargo test --lib')));
    expect(verifyLines, isNot(contains('cargo test --bin foo')));
    expect(verifyLines, isNot(contains('cargo test --doc')));
    expect(verifyLines, isNot(contains('cargo test --bins')));
    expect(verifyLines, isNot(contains('cargo test --workspace')));
    expect(verifyLines, isNot(contains('cargo test --bench')));
    expect(verifyLines, isNot(contains('cargo clippy --lib')));
    expect(verifyLines, isNot(contains('cargo clippy --bins')));
    expect(verifyLines, isNot(contains('cargo clippy --exclude foo')));
    expect(verifyBlock, isNot(contains('clippy --workspace --exclude foo')));
    expect(verifyLines, isNot(contains('cargo clippy --doc')));
    expect(verifyLines, isNot(contains('cargo clippy --workspace --doc')));
    expect(verifyBlock, isNot(contains('workspace --no-default-features')));
    expect(verifyLines, isNot(contains('cargo clippy --all --features foo')));
    expect(verifyBlock, isNot(contains('clippy --workspace --target wasm32')));
    expect(verifyBlock, isNot(contains('cargo clippy -F')));
    expect(verifyBlock, isNot(contains('cargo clippy --features')));
    expect(verifyBlock, isNot(contains('cargo clippy --exclude')));
    expect(verifyBlock, isNot(contains('cargo clippy --target')));
    expect(verifyLines, isNot(contains('cargo test -p*')));
    expect(verifyLines, isNot(contains('cargo test -p *')));
    expect(verifyLines, isNot(contains('cargo test --package *')));
    expect(verifyBlock, isNot(contains('cargo test --features')));
    expect(verifyBlock, isNot(contains('cargo test -F')));
    expect(verifyLines, isNot(contains('cargo test --no-default-features')));
    expect(verifyBlock, isNot(contains('cargo test --target')));
    expect(verifyLines, isNot(contains('cargo test --exclude *')));
    expect(verifyBlock, isNot(contains('clippy -p *')));
    expect(verifyBlock, isNot(contains('clippy --package *')));
    expect(verifyLines, isNot(contains('cargo test -- --ignored')));
    expect(verifyBlock, isNot(contains('-- --skip')));
    expect(verifyLines, isNot(contains('cargo test -- --list')));
    expect(verifyBlock, isNot(contains('--exclude-should-panic')));
    expect(verifyLines, isNot(contains('cargo test -p foo -- --ignored')));
    expect(verifyLines, isNot(contains('cargo test -- --skip foo')));
    expect(verifyLines, isNot(contains('cargo test -- *')));
    expect(verifyLines, isNot(contains('cargo test *')));
    expect(verifyBlock, isNot(contains('--exact')));
    expect(verifyLines, isNot(contains('cargo test --exclude foo')));
    expect(verifyLines, isNot(contains('cargo test --all')));
    expect(verifyBlock, isNot(contains('test-filter')));
    expect(verifyBlock, isNot(contains('--filter *')));
    expect(verifyBlock, isNot(contains('--filter=*')));
    expect(verifyLines, isNot(contains('mvn test -Dtest=*')));
    expect(verifyLines, isNot(contains('./mvnw test -Dtest=*')));
    expect(verifyLines, isNot(contains('mvn test -Dgroups=*')));
    expect(verifyLines, isNot(contains('mvn test -DexcludedGroups=*')));
    expect(verifyLines, isNot(contains('mvn test -Dsurefire.includes=*')));
    expect(verifyLines, isNot(contains('mvn verify -Dit.test=*')));
    expect(verifyLines, isNot(contains('./mvnw test -Dgroups=*')));
    expect(verifyLines, isNot(contains('./mvnw verify -Dit.test=*')));
    expect(verifyLines, isNot(contains('mvn test -DincludesFile=*')));
    expect(verifyLines, isNot(contains('mvn test -DexcludesFile=*')));
    expect(verifyLines, isNot(contains('mvn test -DincludeJUnit5Engines=*')));
    expect(verifyLines, isNot(contains('mvn test -DexcludeJUnit5Engines=*')));
    expect(verifyLines, isNot(contains('./mvnw test -DincludesFile=*')));
    expect(verifyLines, isNot(contains('mvn test -DsuiteXmlFiles=*')));
    expect(verifyLines, isNot(contains('mvn test -DsuiteXmlFiles=testng.xml')));
    expect(verifyLines, isNot(contains('mvn test -Dsurefire.suiteXmlFiles=*')));
    expect(verifyBlock, isNot(contains('failsafe.suiteXmlFiles')));
    expect(verifyLines, isNot(contains('mvn test -DdependenciesToScan=*')));
    expect(verifyBlock, isNot(contains('classpathDependencyExcludes')));
    expect(verifyBlock, isNot(contains('classpathDependencyIncludes')));
    expect(verifyBlock, isNot(contains('maven.test.dependency.excludes')));
    expect(verifyBlock, isNot(contains('classpathDependencyScopeExclude')));
    expect(verifyBlock, isNot(contains('testClassesDirectory=target')));
    expect(verifyBlock, isNot(contains('testSourceDirectory=src/alt')));
    expect(verifyBlock, isNot(contains('surefire.testClassesDirectory')));
    expect(verifyBlock, isNot(contains('failsafe.testSourceDirectory')));
    expect(verifyBlock, isNot(contains('project.build.testOutputDirectory')));
    expect(verifyBlock, isNot(contains('testClasspathElements')));
    expect(verifyBlock, isNot(contains('additionalClasspathElements')));
    expect(verifyBlock, isNot(contains('generatedTestSourcesDirectory')));
    expect(verifyBlock, isNot(contains('-DclassesDirectory=')));
    expect(verifyBlock, isNot(contains('project.build.outputDirectory')));
    expect(verifyLines, isNot(contains('mvn -f other/pom.xml test')));
    expect(verifyLines, isNot(contains('mvn --file other/pom.xml test')));
    expect(verifyLines, isNot(contains('mvn -fother/pom.xml test')));
    expect(verifyBlock, isNot(contains('/workspace/module/pom.xml')));
    expect(verifyLines, isNot(contains('mvn -t toolchains.xml test')));
    expect(verifyBlock, isNot(contains('testFailureIgnore=true')));
    expect(verifyLines, isNot(contains('mvn --fail-never test')));
    expect(verifyLines, isNot(contains('mvn -fn test')));
    expect(verifyBlock, isNot(contains('error.ignore=true')));
    expect(verifyBlock, isNot(contains('D:/a/repo/module/pom.xml')));
    expect(verifyBlock, isNot(contains('D:/a/1/s/module/pom.xml')));
    expect(verifyLines, isNot(contains('./gradlew test --continue')));
    expect(verifyBlock, isNot(contains('--init-script')));
    expect(verifyLines, isNot(contains('./gradlew -I init.gradle test')));
    expect(verifyBlock, isNot(contains('org.gradle.continue=true')));
    expect(verifyLines, isNot(contains('./gradlew -g /tmp/ghome test')));
    expect(verifyBlock, isNot(contains('--gradle-user-home')));
    expect(verifyBlock, isNot(contains('ignoreFailures=true')));
    expect(verifyBlock, isNot(contains('failOnNoMatchingTests=false')));
    expect(verifyBlock, isNot(contains('test.single=Foo')));
    expect(verifyLines, isNot(contains('cargo test --no-fail-fast')));
    expect(verifyLines, isNot(contains('jest --passWithNoTests')));
    expect(verifyBlock, isNot(contains('-Ptest.single=Foo')));
    expect(verifyBlock, isNot(contains('failIfNoTests=false')));
    expect(verifyLines, isNot(contains('make -i test')));
    expect(verifyLines, isNot(contains('make -ik test')));
    expect(verifyLines, isNot(contains('make -ks test')));
    expect(verifyLines, isNot(contains('make test TESTS=foo')));
    expect(verifyLines, isNot(contains('ctest -R Foo')));
    expect(verifyLines, isNot(contains('ctest --no-tests=ignore')));
    expect(verifyLines, isNot(contains('pytest --lf')));
    expect(verifyLines, isNot(contains('yarn test --onlyFailures')));
    expect(verifyLines, isNot(contains('npm run test:unit -- -t Foo')));
    expect(verifyLines, isNot(contains('go test -short')));
    expect(verifyLines, isNot(contains('jest --watch')));
    expect(verifyLines, isNot(contains('rspec -P foo')));
    expect(verifyLines, isNot(contains('npm test -- --dir=src')));
    expect(verifyLines, isNot(contains('vitest --project foo')));
    expect(verifyBlock, isNot(contains('commandLineIncludePatterns')));
    expect(verifyBlock, isNot(contains('/workspace/module/build.gradle')));
    expect(verifyLines, isNot(contains('./gradlew -p /workspace test')));
    expect(verifyLines, isNot(contains('./gradlew -p other test')));
    expect(verifyLines, isNot(contains('./gradlew test -p')));
    expect(verifyBlock, isNot(contains('-b other.gradle')));
    expect(verifyLines, isNot(contains('./gradlew -p= test')));
    expect(verifyBlock, isNot(contains('-c other.settings.gradle')));
    expect(verifyBlock, isNot(contains('--include-build')));
    expect(verifyBlock, isNot(contains('basedir=/other')));
    expect(verifyLines, isNot(contains('mvn test -Dbasedir')));
    expect(verifyBlock, isNot(contains('/home/vsts/work/1/s/module/pom.xml')));
    expect(verifyBlock, isNot(contains('multiModuleProjectDirectory')));
    expect(verifyLines, isNot(contains('mvn -s settings.xml test')));
    expect(verifyLines, isNot(contains('mvn -Pprod test')));
    expect(verifyLines, isNot(contains('mvn test -pl :foo')));
    expect(verifyLines, isNot(contains('mvn -N test')));
    expect(verifyBlock, isNot(contains('generatedSourcesDirectory')));
    expect(verifyLines, isNot(contains('pytest -k=*')));
    expect(verifyLines, isNot(contains('flutter test --name=*')));
    expect(verifyLines, isNot(contains('jest -t=*')));
    expect(verifyBlock, isNot(contains('surefire.skip')));
    expect(verifyBlock, isNot(contains('-Dtest=Nope')));
    expect(verifyBlock, isNot(contains('--tests Nope')));
    expect(verifyBlock, isNot(contains('go test -run Nope')));
    expect(verifyBlock, isNot(contains('cargo test nope')));
    expect(verifyBlock, isNot(contains('pytest -k nope')));
    expect(verifyBlock, isNot(contains('test/foo_test.dart')));
    expect(verifyBlock, isNot(contains('--name Foo')));
    expect(verifyBlock, isNot(contains('pytest -m nope')));
    expect(verifyBlock, isNot(contains('cargo test -p foo')));
    expect(verifyBlock, isNot(contains('go test ./pkg')));
    expect(verifyBlock, isNot(contains('*Test*')));
  });
}
