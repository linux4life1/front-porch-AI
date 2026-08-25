// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Per-alternate-greeting Realism/Needs overlays. Proven red first: before
// greetingOverlayAt / resolveGreetingOpening existed, an angry alt inherited
// the friend first_mes seed (or fired reading-the-room and never restored).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

void main() {
  final angry = GreetingRealismSeed(
    characterEmotion: 'furious',
    emotionIntensity: 'strong',
    shortTermBond: -40,
    trustLevel: -20,
    timeOfDay: 'night',
    needsBaselineHunger: 30,
  );

  test(
    'overlay index 0 is always the card (first_mes), not greeting_seeds[0]',
    () {
      expect(
        greetingOverlayAt([angry], 0),
        isNull,
        reason: 'first_mes keeps using card-level realism_engine fields',
      );
      expect(greetingOverlayAt([angry], 1), angry);
    },
  );

  test(
    'a missing alt slot is unauthored (read-the-room); {} is authored inherit',
    () {
      expect(
        greetingHasAuthoredSeed(
          hasCardExtensions: true,
          seeds: const [null],
          greetingIndex: 1,
        ),
        isFalse,
      );
      expect(
        greetingHasAuthoredSeed(
          hasCardExtensions: true,
          seeds: [const GreetingRealismSeed()],
          greetingIndex: 1,
        ),
        isTrue,
      );
    },
  );

  test('merge overlays sparse fields onto the card base', () {
    const base = GreetingOpeningBase(
      shortTermBond: 20,
      characterEmotion: 'warm',
      emotionIntensity: 'mild',
      timeOfDay: 'morning',
      needsBaselineHunger: 80,
    );
    final resolved = resolveGreetingOpening(base, angry);
    expect(resolved.characterEmotion, 'furious');
    expect(resolved.emotionIntensity, 'strong');
    expect(resolved.shortTermBond, -40);
    expect(resolved.trustLevel, -20);
    expect(resolved.timeOfDay, 'night');
    expect(resolved.needsBaselineHunger, 30);
    expect(
      resolved.needsBaselineBladder,
      80,
      reason: 'unmentioned needs inherit',
    );
    expect(resolved.longTermBond, 0, reason: 'unmentioned bond inherits');
  });

  test(
    'swiping back to 0 is resolve(base, null) — friend mood, not leftover fury',
    () {
      const base = GreetingOpeningBase(
        characterEmotion: 'warm',
        shortTermBond: 20,
      );
      final back = resolveGreetingOpening(base, greetingOverlayAt([angry], 0));
      expect(back.characterEmotion, 'warm');
      expect(back.shortTermBond, 20);
    },
  );

  test('card JSON round-trips greeting_seeds including a null hole', () {
    final ext = FrontPorchExtensions(
      characterEmotion: 'warm',
      greetingSeeds: [angry, null, const GreetingRealismSeed()],
    );
    final restored = FrontPorchExtensions.fromJson(ext.toJson());
    expect(restored.greetingSeeds, hasLength(3));
    expect(restored.greetingSeeds[0]!.characterEmotion, 'furious');
    expect(restored.greetingSeeds[1], isNull);
    expect(restored.greetingSeeds[2], isNotNull);
    expect(restored.greetingSeeds[2]!.isEmpty, isTrue);
  });

  test('recoverGreetingIndex prefers stamped metadata then text match', () {
    expect(
      recoverGreetingIndex(
        resolvedGreetings: ['hi', 'hey', 'yo'],
        currentText: 'hey',
        storedIndex: 2,
      ),
      2,
    );
    expect(
      recoverGreetingIndex(
        resolvedGreetings: ['hi', 'hey', 'yo'],
        currentText: 'hey',
        storedIndex: null,
      ),
      1,
    );
  });

  test(
    'a web save that never mentions greetingSeeds keeps the base overlays',
    () {
      final seeded = FrontPorchExtensions(greetingSeeds: [angry]);
      final back = frontPorchFromFields(const {
        'realismEnabled': true,
        'trustLevel': 5,
      }, base: seeded);
      expect(back.greetingSeeds, hasLength(1));
      expect(back.greetingSeeds.first!.characterEmotion, 'furious');
      expect(back.trustLevel, 5);
    },
  );

  test('web round-trip of greetingSeeds is lossless', () {
    final original = FrontPorchExtensions(greetingSeeds: [angry]);
    final back = frontPorchFromFields(frontPorchToJson(original));
    expect(back.greetingSeeds.first!.characterEmotion, 'furious');
    expect(back.greetingSeeds.first!.shortTermBond, -40);
    expect(back.greetingSeeds.first!.needsBaselineHunger, 30);
  });

  test('empty overlay inherits every card field including wardrobe', () {
    const base = GreetingOpeningBase(
      characterEmotion: 'warm',
      emotionIntensity: 'mild',
      shortTermBond: 20,
      trustLevel: 10,
      timeOfDay: 'morning',
      needsBaselineHunger: 80,
      inventory: {
        'worn': [
          {'name': 'flour-dusted apron'},
        ],
      },
    );
    final resolved = resolveGreetingOpening(base, const GreetingRealismSeed());
    expect(resolved.characterEmotion, 'warm');
    expect(resolved.emotionIntensity, 'mild');
    expect(resolved.shortTermBond, 20);
    expect(resolved.trustLevel, 10);
    expect(resolved.timeOfDay, 'morning');
    expect(resolved.needsBaselineHunger, 80);
    expect(resolved.inventory, base.inventory);
  });

  test('compactGreetingPairs drops empty greet rows with their seed slots', () {
    final furious = GreetingRealismSeed(characterEmotion: 'furious');
    // Add / blank / Add / "Get out." / seed furious
    final paired = compactGreetingPairs(['', 'Get out.'], [null, furious]);
    expect(paired.greetings, ['Get out.']);
    expect(paired.seeds, hasLength(1));
    expect(
      paired.seeds.first!.characterEmotion,
      'furious',
      reason: 'furious must stay on Get out., not shift onto the blank row',
    );
  });

  test('leftover furious on a blank greet row does not land on Get out', () {
    final furious = GreetingRealismSeed(characterEmotion: 'furious');
    // Dirty ['', 'Get out.'] + [furious]: blank row drops WITH its seed slot.
    final paired = compactGreetingPairs(['', 'Get out.'], [furious]);
    expect(paired.greetings, ['Get out.']);
    expect(
      paired.seeds,
      isEmpty,
      reason:
          'furious sat on the blank; unpaired prefix-align would load it onto Get out',
    );
  });

  test(
    'prefix-align after dropping empty greets is the bug compactGreetingPairs fixes',
    () {
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      final greets = ['', 'Get out.'];
      final alts = [
        for (final g in greets)
          if (g.trim().isNotEmpty) g,
      ];
      final wrong = alignGreetingSeeds([null, furious], alts.length);
      expect(
        wrong.first,
        isNull,
        reason: 'old prefix-align drops furious; compactGreetingPairs must not',
      );
    },
  );

  test(
    'a blank middle row does not pair its seed with neighboring Get out',
    () {
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      final paired = compactGreetingPairs(
        ['Come in.', '', 'Get out.'],
        [null, GreetingRealismSeed(characterEmotion: 'stolen'), furious],
      );
      expect(paired.greetings, ['Come in.', 'Get out.']);
      expect(paired.seeds, hasLength(2));
      expect(paired.seeds[0], isNull);
      expect(
        paired.seeds[1]!.characterEmotion,
        'furious',
        reason: 'blank row must drop with its slot; furious stays on Get out.',
      );
    },
  );

  test(
    'parseGroupAlternateGreetings and parseGroupGreetingSeeds share compactGreetingPairs',
    () {
      final blobs = File(
        'lib/utils/group_realism_blobs.dart',
      ).readAsStringSync();
      final alt = RegExp(
        r'List<String> parseGroupAlternateGreetings\(String defaultMemberJson\) \{([^}]+)\}',
      ).firstMatch(blobs);
      final seeds = RegExp(
        r'List<GreetingRealismSeed\?> parseGroupGreetingSeeds\(String defaultMemberJson\) \{([^}]+)\}',
      ).firstMatch(blobs);
      expect(alt, isNotNull);
      expect(seeds, isNotNull);
      expect(
        alt!.group(1),
        contains('parseGroupOpeningPairs'),
        reason: 'alts must not compact greetings without the paired seed slots',
      );
      expect(
        seeds!.group(1),
        contains('parseGroupOpeningPairs'),
        reason: 'seeds must not parse greetingSeeds without the paired greets',
      );
      expect(
        blobs.contains(
          "return compactGreetingPairs(greets, parseGreetingSeeds(map['greetingSeeds']));",
        ),
        isTrue,
        reason: 'the shared helper is the compactGreetingPairs pairing',
      );

      final group = File('lib/models/group_chat.dart').readAsStringSync();
      expect(
        group.contains('compactGreetingPairs'),
        isTrue,
        reason: 'GroupChat.fromJson must use the same pairing',
      );
    },
  );

  test(
    'FrontPorchExtensions.fromJson pairs empty-greet drop with compactGreetingPairs',
    () {
      final dirty = FrontPorchExtensions.fromJson(
        {
          'realism_engine': {
            'enabled': true,
            'greeting_seeds': [
              {'character_emotion': 'furious'},
            ],
          },
        },
        alternateGreetings: ['', 'Get out.'],
      );
      expect(
        dirty.greetingSeeds,
        isEmpty,
        reason: "['', 'Get out.']+[furious] must not load furious onto Get out",
      );
      expect(greetingOverlayAt(dirty.greetingSeeds, 1), isNull);

      final kept = FrontPorchExtensions.fromJson(
        {
          'realism_engine': {
            'enabled': true,
            'greeting_seeds': [
              null,
              {'character_emotion': 'furious'},
            ],
          },
        },
        alternateGreetings: ['', 'Get out.'],
      );
      expect(kept.greetingSeeds, hasLength(1));
      expect(kept.greetingSeeds.first!.characterEmotion, 'furious');

      // Extra: fromJson must call compactGreetingPairs when alts are present.
      final fromJsonSrc = File('lib/models/character_card.dart').readAsStringSync();
      expect(
        fromJsonSrc.contains(
          'return compactGreetingPairs(alternateGreetings, parsed).seeds;',
        ),
        isTrue,
        reason: '1:1 fromJson pairs through compactGreetingPairs, not prefix-align',
      );
    },
  );

  test(
    'toJson/fromJson without alts keeps sparse seed holes',
    () {
      final ext = FrontPorchExtensions(
        greetingSeeds: [
          null,
          GreetingRealismSeed(characterEmotion: 'furious'),
          null,
          const GreetingRealismSeed(),
        ],
      );
      final json = ext.toJson();
      final seedsJson =
          (json['realism_engine'] as Map)['greeting_seeds'] as List;
      expect(
        seedsJson,
        hasLength(4),
        reason: 'toJson must keep internal holes; only trailing nulls compact',
      );
      expect(seedsJson[0], isNull);
      expect(seedsJson[2], isNull);

      final restored = FrontPorchExtensions.fromJson(json);
      expect(
        restored.greetingSeeds,
        hasLength(4),
        reason: 'no-alts fromJson must not compact-pair holes away',
      );
      expect(restored.greetingSeeds[0], isNull);
      expect(restored.greetingSeeds[1]!.characterEmotion, 'furious');
      expect(restored.greetingSeeds[2], isNull);
      expect(restored.greetingSeeds[3], isNotNull);
      expect(restored.greetingSeeds[3]!.isEmpty, isTrue);

      final emptyAlts = FrontPorchExtensions.fromJson(
        json,
        alternateGreetings: const [],
      );
      expect(
        emptyAlts.greetingSeeds,
        hasLength(4),
        reason: 'explicit empty alts must still preserve sparse seed holes',
      );
      expect(emptyAlts.greetingSeeds[0], isNull);
      expect(emptyAlts.greetingSeeds[1]!.characterEmotion, 'furious');
      expect(greetingOverlayAt(emptyAlts.greetingSeeds, 1), isNull);
      expect(
        greetingOverlayAt(emptyAlts.greetingSeeds, 2)!.characterEmotion,
        'furious',
      );
    },
  );

  test(
    'frontPorchFromFields pairs dirty empty greet so furious does not land on Get out',
    () {
      final back = frontPorchFromFields({
        'alternateGreetings': ['', 'Get out.'],
        'greetingSeeds': [
          {'characterEmotion': 'furious'},
        ],
      });
      expect(
        back.greetingSeeds,
        isEmpty,
        reason: "['', 'Get out.']+[furious] must not load furious onto Get out",
      );
      expect(greetingOverlayAt(back.greetingSeeds, 1), isNull);
    },
  );

  test(
    'frontPorchFromFields omitted seeds + dirty alts drop leftover base furious',
    () {
      final seeded = FrontPorchExtensions(greetingSeeds: [angry]);
      final dirty = frontPorchFromFields({
        'alternateGreetings': ['', 'Get out.'],
      }, base: seeded);
      expect(
        dirty.greetingSeeds,
        isEmpty,
        reason:
            'alts-only POST must compact against empty seeds, not keep unpaired [furious]',
      );
      expect(
        greetingOverlayAt(dirty.greetingSeeds, 1),
        isNull,
        reason: 'Get out overlay must not be leftover furious',
      );

      final clean = frontPorchFromFields({
        'alternateGreetings': ['Get out.'],
      }, base: seeded);
      expect(
        clean.greetingSeeds,
        isEmpty,
        reason: "['Get out.'] omit seeds must not reuse unpaired base [furious]",
      );
      expect(greetingOverlayAt(clean.greetingSeeds, 1), isNull);

      final authoredEmpty = frontPorchFromFields({
        'alternateGreetings': ['', 'Get out.'],
        'greetingSeeds': [],
      }, base: seeded);
      expect(
        authoredEmpty.greetingSeeds,
        isEmpty,
        reason: 'explicit empty greetingSeeds is authored-empty, not keep base',
      );
    },
  );

  test(
    'frontPorchFromFields explicit empty greetingSeeds stays authored-empty',
    () {
      final seeded = FrontPorchExtensions(greetingSeeds: [angry]);
      final withAlts = frontPorchFromFields({
        'alternateGreetings': ['', 'Get out.'],
        'greetingSeeds': [],
      }, base: seeded);
      expect(
        withAlts.greetingSeeds,
        isEmpty,
        reason:
            'explicit empty greetingSeeds is authored-empty, not leftover furious',
      );
      expect(greetingOverlayAt(withAlts.greetingSeeds, 1), isNull);

      final noAlts = frontPorchFromFields({
        'greetingSeeds': [],
        'trustLevel': 3,
      }, base: seeded);
      expect(
        noAlts.greetingSeeds,
        isEmpty,
        reason: 'explicit empty is authored-empty, not dropped as omit',
      );
      expect(noAlts.trustLevel, 3);
    },
  );

  test(
    'frontPorchFromFields omitted alts keep base seeds',
    () {
      final seeded = FrontPorchExtensions(greetingSeeds: [angry]);
      final back = frontPorchFromFields({
        'trustLevel': 5,
        'realismEnabled': true,
      }, base: seeded);
      expect(back.greetingSeeds, hasLength(1));
      expect(
        back.greetingSeeds.first!.characterEmotion,
        'furious',
        reason: 'omitted alts must not wipe leftover base seeds',
      );
      expect(back.trustLevel, 5);
    },
  );

  test(
    'omitted greetingSeeds become empty/null before compact at both call sites',
    () {
      final fp = File(
        'lib/services/web/util/realism_extensions_json.dart',
      ).readAsStringSync();
      final omitted = RegExp(
        r"if \(!fields\.containsKey\('greetingSeeds'\)\) \{([^}]+)\}",
      ).firstMatch(fp);
      expect(omitted, isNotNull);
      final body = omitted!.group(1)!;
      expect(
        body.contains('if (!altsPresent) return b.greetingSeeds;'),
        isTrue,
        reason: 'omitted alts still keep base seeds',
      );
      expect(
        body.contains('const []'),
        isTrue,
        reason: 'omitted seeds + alts compact against empty, not leftover',
      );
      expect(body.contains('compactGreetingPairs'), isTrue);
      expect(
        RegExp(r'compactGreetingPairs\([^)]*b\.greetingSeeds').hasMatch(body),
        isFalse,
        reason: 'must not compact against leftover base seeds',
      );

      final chars = File(
        'lib/services/web/facade/character_facade.dart',
      ).readAsStringSync();
      final updateCompact = RegExp(
        r"compactGreetingPairs\(\s*greetingSlotsFromRaw\(greetings\),\s*"
        r"fields\.containsKey\('greetingSeeds'\)\s*"
        r"\? parseGreetingSeeds\(fields\['greetingSeeds'\]\)\s*"
        r": const \[\],",
      );
      expect(
        updateCompact.hasMatch(chars),
        isTrue,
        reason:
            'facade.update omitted seeds must pass empty to compact, not leftover',
      );

      final groups = File(
        'lib/services/web/facade/group_facade.dart',
      ).readAsStringSync();
      final groupCompact = RegExp(
        r"f\.containsKey\('greetingSeeds'\)\s*"
        r"\? parseGreetingSeeds\(f\['greetingSeeds'\]\)\s*"
        r": const \[\],",
      );
      expect(
        groupCompact.hasMatch(groups),
        isTrue,
        reason:
            'group updateSettings omitted seeds must pass empty to compact, not leftover',
      );
      expect(
        RegExp(r': g\.greetingSeeds,').hasMatch(groups),
        isFalse,
        reason: 'must not compact alts-only against unpaired existing g.greetingSeeds',
      );
    },
  );

  test(
    'JSON-null greet slots stay as placeholders so zip keeps furious on Get out',
    () {
      final slots = greetingSlotsFromRaw([null, 'Get out.']);
      expect(slots, ['', 'Get out.']);
      final paired = compactGreetingPairs(
        slots,
        parseGreetingSeeds([
          null,
          {'character_emotion': 'furious'},
        ]),
      );
      expect(paired.greetings, ['Get out.']);
      expect(
        paired.seeds.single!.characterEmotion,
        'furious',
        reason: 'null greet dropped with its null seed; Get out keeps furious',
      );

      final web = frontPorchFromFields({
        'alternateGreetings': [null, 'Get out.'],
        'greetingSeeds': [
          null,
          {'characterEmotion': 'furious'},
        ],
      });
      expect(web.greetingSeeds, hasLength(1));
      expect(web.greetingSeeds.single!.characterEmotion, 'furious');
    },
  );

  test(
    'characters.md pins first_mes, skip-RtR, {} vs null, swipe-0, groups 1:1',
    () {
      final md = File('docs/characters.md').readAsStringSync();
      expect(md.contains('first_mes'), isTrue);
      expect(md.contains('Reads the Room'), isTrue);
      expect(md.contains('including empty `{}`'), isTrue);
      expect(md.contains('Swipe 0'), isTrue);
      expect(md.contains('Groups match 1:1'), isTrue);
      expect(
        md.contains('must not write `{}` just because the seed toggle is on'),
        isTrue,
      );
    },
  );

  test(
    'web/API call sites pair dirty greets through compactGreetingPairs',
    () {
      final fp = File('lib/services/web/util/realism_extensions_json.dart')
          .readAsStringSync();
      expect(fp.contains('compactGreetingPairs'), isTrue);
      expect(fp.contains('greetingSlotsFromRaw'), isTrue);

      final chars = File('lib/services/web/facade/character_facade.dart')
          .readAsStringSync();
      expect(chars.contains('compactGreetingPairs'), isTrue);
      expect(chars.contains('greetingSlotsFromRaw'), isTrue);

      final groups = File('lib/services/web/facade/group_facade.dart')
          .readAsStringSync();
      expect(groups.contains('compactGreetingPairs'), isTrue);
      expect(groups.contains('greetingSlotsFromRaw'), isTrue);

      final enhance = File(
        'lib/services/chargen/character_gen_enhance.dart',
      ).readAsStringSync();
      expect(
        enhance.contains('assignRewrittenAlternateGreetings'),
        isTrue,
        reason: 'enhance must assign rewritten alts via compact-empty, not bare =',
      );
      expect(
        enhance.contains('greetingSeeds: compactRewrittenGreetingAlts'),
        isTrue,
        reason:
            'copyWith after alt rewrite must pass compact-empty/authored seeds',
      );

      final chargen = File(
        'lib/services/character_gen_service.dart',
      ).readAsStringSync();
      expect(
        chargen.contains('assignRewrittenAlternateGreetings'),
        isTrue,
        reason: 'chargen must assign rewritten alts via compact-empty, not bare =',
      );
      expect(
        chargen.contains('card.alternateGreetings = alts;'),
        isFalse,
        reason: 'bare alt assign keeps leftover source seeds',
      );

      final review = File(
        'lib/ui/pages/home/enhance/enhance_review_body.dart',
      ).readAsStringSync();
      expect(
        review.contains('ext?.greetingSeeds'),
        isFalse,
        reason: 'must not compact accepted greets against leftover copy seeds',
      );
      expect(review.contains('compactAcceptedEnhanceGreetings'), isTrue);
      expect(
        review.contains(
          'widget.enhanced.frontPorchExtensions?.greetingSeeds',
        ),
        isTrue,
        reason: 'review must pair against enhance-authored seeds, or empty',
      );
    },
  );

  test(
    'compactRewrittenGreetingAlts omits leftover furious on Get out',
    () {
      final leftover = [angry];
      final omitted = compactRewrittenGreetingAlts(['Get out.']);
      expect(omitted.greetings, ['Get out.']);
      expect(
        omitted.seeds,
        isEmpty,
        reason: "['Get out.'] omit seeds must not reuse unpaired [furious]",
      );
      expect(
        greetingOverlayAt(omitted.seeds, 1),
        isNull,
        reason: 'Get out overlay is not leftover furious',
      );
      expect(
        leftover.single.characterEmotion,
        'furious',
        reason: 'source leftover stays on the source list, not the compact',
      );
    },
  );

  test(
    'compactRewrittenGreetingAlts pairs a seed the enhance step authored',
    () {
      final authored = [GreetingRealismSeed(characterEmotion: 'cold')];
      final paired = compactRewrittenGreetingAlts(['Get out.'], authored);
      expect(paired.greetings, ['Get out.']);
      expect(paired.seeds.single!.characterEmotion, 'cold');
      expect(
        greetingOverlayAt(paired.seeds, 1)!.characterEmotion,
        'cold',
      );
    },
  );

  test(
    'assignRewrittenAlternateGreetings drops leftover source furious on Get out',
    () {
      final card = CharacterCard(
        name: 'Nina',
        alternateGreetings: ['Stay.'],
        frontPorchExtensions: FrontPorchExtensions(greetingSeeds: [angry]),
      );
      card.assignRewrittenAlternateGreetings(['Get out.']);
      expect(card.alternateGreetings, ['Get out.']);
      expect(
        card.frontPorchExtensions!.greetingSeeds,
        isEmpty,
        reason:
            "['Get out.'] omit seeds must not reuse unpaired source [furious]",
      );
      expect(
        greetingOverlayAt(card.frontPorchExtensions!.greetingSeeds, 1),
        isNull,
        reason: 'Get out overlay is not leftover furious',
      );
    },
  );

  test(
    'assignRewrittenAlternateGreetings keeps a seed authored with the new alts',
    () {
      final card = CharacterCard(
        name: 'Nina',
        alternateGreetings: ['Stay.'],
        frontPorchExtensions: FrontPorchExtensions(greetingSeeds: [angry]),
      );
      card.assignRewrittenAlternateGreetings(
        ['Get out.'],
        authoredSeeds: [GreetingRealismSeed(characterEmotion: 'cold')],
      );
      expect(card.alternateGreetings, ['Get out.']);
      expect(
        card.frontPorchExtensions!.greetingSeeds.single!.characterEmotion,
        'cold',
      );
    },
  );

  test(
    'empty first_mes: displayed 0 is alt[0]/seeds[0], not a null card overlay',
    () {
      final warm = GreetingRealismSeed(characterEmotion: 'warm');
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      expect(
        greetingOverlayAt([warm, furious], 0),
        isNull,
        reason: 'first_mes-with-text still uses the card seed',
      );
      expect(greetingOverlayAt([warm, furious], 1), warm);
      expect(
        greetingOverlayAt([warm, furious], 0, firstMesEmpty: true),
        warm,
        reason: 'empty first_mes: Stay. is displayed 0 and reads seeds[0]',
      );
      expect(
        greetingOverlayAt([warm, furious], 1, firstMesEmpty: true),
        furious,
        reason: 'empty first_mes: Get out. reads seeds[1], not leftover warm',
      );
      expect(
        greetingHasAuthoredSeed(
          hasCardExtensions: true,
          seeds: [warm, furious],
          greetingIndex: 0,
          firstMesEmpty: true,
        ),
        isTrue,
      );
    },
  );

  test(
    'whitespace-only first_mes pairs like empty: displayed 0 is seeds[0]',
    () {
      final warm = GreetingRealismSeed(characterEmotion: 'warm');
      final furious = GreetingRealismSeed(characterEmotion: 'furious');
      expect(greetingFirstMesEmpty(''), isTrue);
      expect(greetingFirstMesEmpty('   '), isTrue);
      expect(greetingFirstMesEmpty('\n'), isTrue);
      expect(greetingFirstMesEmpty('  \n'), isTrue);
      expect(greetingFirstMesEmpty('Hello'), isFalse);
      expect(greetingFirstMesEmpty(' Hello '), isFalse);
      expect(
        greetingOverlayAt(
          [warm, furious],
          0,
          firstMesEmpty: greetingFirstMesEmpty('   '),
        ),
        warm,
        reason: "first_mes '   ': Stay. is displayed 0 and reads seeds[0]",
      );
      expect(
        greetingOverlayAt(
          [warm, furious],
          1,
          firstMesEmpty: greetingFirstMesEmpty('   '),
        ),
        furious,
        reason: "first_mes '   ': Get out. reads seeds[1], not leftover warm",
      );
    },
  );

  test('CharacterCard.allGreetings drops whitespace-only first_mes', () {
    final card = CharacterCard(
      name: 'Nemu',
      firstMessage: '   ',
      alternateGreetings: const ['Stay.', 'Get out.'],
    );
    expect(card.allGreetings, ['Stay.', 'Get out.']);
    expect(
      CharacterCard(
        name: 'Nemu',
        firstMessage: 'Hello, friend.',
        alternateGreetings: const ['Get out.'],
      ).allGreetings,
      ['Hello, friend.', 'Get out.'],
      reason: 'real non-whitespace first_mes stays displayed 0',
    );
  });

  test('GroupChat.allGreetings drops whitespace-only first_mes', () {
    expect(
      GroupChat(
        id: 'g',
        name: 'House',
        firstMessage: '   ',
        alternateGreetings: const ['Stay.', 'Get out.'],
      ).allGreetings,
      ['Stay.', 'Get out.'],
    );
    expect(
      GroupChat(
        id: 'g2',
        name: 'House',
        firstMessage: 'Come in.',
        alternateGreetings: const ['Get out.'],
      ).allGreetings,
      ['Come in.', 'Get out.'],
      reason: 'real non-whitespace group first_mes stays displayed 0',
    );
  });

}
