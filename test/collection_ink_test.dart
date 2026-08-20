import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memai_android/theme/mem_app_theme.dart';
import 'package:memai_android/theme/mem_collection_ink.dart';
import 'package:memai_android/theme/mem_semantic_colors.dart';

/// Golden hashes for the FNV-1a ramp mapping.
///
/// These are **contract values**, not observations: the collection ink is
/// derived client-side and must be stable across sessions, devices, and app
/// versions. If a change to [collectionInkIndex] moves any of these, every
/// user's collections silently change colour.
const Map<String, int> _goldenIndices = <String, int>{
  '': 5, // the bare FNV-1a offset basis, 0x811c9dc5 % 8
  'a': 4,
  'abc': 5,
  'collection-1': 7,
  'Interviews': 7,
  '00000000-0000-0000-0000-000000000000': 5,
  '01H8XGJWBWBAQ4ZVQ1V2NR3S1M': 5,
  'Reading List': 5,
  'work': 4,
  'Ideas': 7,
  'inbox': 7,
  'Projects': 3,
};

void main() {
  group('collectionInkIndex — FNV-1a mod 8', () {
    test('is deterministic: the same id always lands on the same slot', () {
      const List<String> ids = <String>[
        'alpha',
        'beta',
        'a-very-long-collection-identifier-0123456789',
        'ünïcödé 🎧',
      ];
      for (final String id in ids) {
        final int first = collectionInkIndex(id);
        for (int i = 0; i < 50; i++) {
          expect(
            collectionInkIndex(id),
            first,
            reason: 'ink index for "$id" drifted between calls',
          );
        }
      }
    });

    test('matches the golden mapping (never re-hash to dodge a collision)', () {
      _goldenIndices.forEach((String id, int expected) {
        expect(collectionInkIndex(id), expected, reason: 'id "$id"');
      });
    });

    test('always lands inside the ramp, for any id shape', () {
      final List<String> ids = <String>[
        '',
        ' ',
        '\n',
        'x' * 512,
        '🎧🎧🎧',
        for (int i = 0; i < 2000; i++) 'col-$i',
      ];
      for (final String id in ids) {
        final int index = collectionInkIndex(id);
        expect(index, greaterThanOrEqualTo(0), reason: 'id "$id"');
        expect(index, lessThan(kMemCollectionInkCount), reason: 'id "$id"');
      }
    });

    test('the mod-8 mapping uses every slot', () {
      final Set<int> hit = <int>{};
      for (int i = 0; i < 2000; i++) {
        hit.add(collectionInkIndex('col-$i'));
      }
      expect(hit, hasLength(kMemCollectionInkCount));
    });

    test('collisions are kept, never perturbed away', () {
      // Past 8 collections two of them share an ink by design. The rule is
      // that stability beats uniqueness: colliding ids must keep returning
      // their colliding slot, because colour is never the sole signifier —
      // every tag renders the collection title beside the dot.
      expect(collectionInkIndex('Ideas'), 7);
      expect(collectionInkIndex('ideas'), 7);
      expect(collectionInkIndex('collection-1'), 7);
    });
  });

  group('the ramp itself', () {
    test('both brightnesses are exactly 8 long, same slot names, same order', () {
      expect(memCollectionInksDark, hasLength(kMemCollectionInkCount));
      expect(memCollectionInksLight, hasLength(kMemCollectionInkCount));
      expect(
        memCollectionInksDark.map((CollectionInk i) => i.name).toList(),
        <String>[
          'Blue',
          'Cyan',
          'Teal',
          'Green',
          'Amber',
          'Coral',
          'Pink',
          'Slate',
        ],
      );
      expect(
        memCollectionInksLight.map((CollectionInk i) => i.name).toList(),
        memCollectionInksDark.map((CollectionInk i) => i.name).toList(),
      );
    });

    test('memCollectionInksFor picks the right ramp', () {
      expect(memCollectionInksFor(Brightness.dark), same(memCollectionInksDark));
      expect(
        memCollectionInksFor(Brightness.light),
        same(memCollectionInksLight),
      );
    });

    test('every slot is a distinct explicit pair — no alpha blends', () {
      for (final Brightness b in Brightness.values) {
        final List<CollectionInk> ramp = memCollectionInksFor(b);
        expect(
          ramp.map((CollectionInk i) => i.fg).toSet(),
          hasLength(kMemCollectionInkCount),
          reason: '${b.name} foregrounds must all differ',
        );
        expect(
          ramp.map((CollectionInk i) => i.bg).toSet(),
          hasLength(kMemCollectionInkCount),
          reason: '${b.name} backgrounds must all differ',
        );
        for (final CollectionInk ink in ramp) {
          expect(
            ink.fg.a,
            1.0,
            reason: '${b.name} ${ink.name} fg must be fully opaque',
          );
          expect(
            ink.bg.a,
            1.0,
            reason: '${b.name} ${ink.name} bg must be fully opaque',
          );
        }
      }
    });

    test('no violet in the ramp — violet is reserved for AI provenance', () {
      for (final Brightness b in Brightness.values) {
        final Color ai = MemSemanticColors.of(b).aiAccent;
        for (final CollectionInk ink in memCollectionInksFor(b)) {
          expect(ink.fg, isNot(ai), reason: '${b.name} ${ink.name}');
          expect(ink.bg, isNot(MemSemanticColors.of(b).aiContainer));
        }
      }
    });

    test('CollectionInk lerp interpolates ends exactly', () {
      final CollectionInk a = memCollectionInksDark[0];
      final CollectionInk b = memCollectionInksDark[4];
      expect(CollectionInk.lerp(a, b, 0), a);
      expect(CollectionInk.lerp(a, b, 1), b);
      expect(
        CollectionInk.lerpRamp(memCollectionInksDark, memCollectionInksLight, 0),
        memCollectionInksDark,
      );
    });
  });

  group('collectionInkFor(context, id)', () {
    Future<CollectionInk> resolve(
      WidgetTester tester,
      Brightness brightness,
      String id,
    ) async {
      late CollectionInk resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildMemTheme(brightness),
          home: Builder(
            builder: (BuildContext context) {
              resolved = collectionInkFor(context, id);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return resolved;
    }

    testWidgets('reads the current brightness ramp at the hashed index', (
      WidgetTester tester,
    ) async {
      for (final Brightness b in Brightness.values) {
        for (final String id in _goldenIndices.keys) {
          final CollectionInk ink = await resolve(tester, b, id);
          expect(
            ink,
            memCollectionInksFor(b)[_goldenIndices[id]!],
            reason: '${b.name} id "$id"',
          );
        }
      }
    });

    testWidgets('the same id keeps its slot name across both themes', (
      WidgetTester tester,
    ) async {
      const String id = 'Interviews';
      final CollectionInk dark = await resolve(tester, Brightness.dark, id);
      final CollectionInk light = await resolve(tester, Brightness.light, id);
      expect(dark.name, light.name);
      expect(dark.fg, isNot(light.fg));
    });
  });
}
