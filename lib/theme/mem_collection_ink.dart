import 'package:flutter/material.dart';

import 'mem_semantic_colors.dart';

/// The collection ink ramp.
///
/// **Colour is a derived presentation token, never API data.** The Mem data
/// model has no colour or emoji field on a collection (`MemCollectionItem` is
/// `id/title/description/noteCount/createdAt/updatedAt`), so the ink is
/// computed client-side from the collection id and is stable forever: the same
/// id lands on the same ink across sessions, devices, and screens.
///
/// The ramp is 8 explicit `(fg, bg)` pairs **per brightness** — never an
/// alpha-blended fill — so label contrast is deterministic on every surface a
/// tag can land on. All 16 pairs clear 4.5 : 1 at label size
/// (`labelMedium`, 12 sp w600); `test/theme_contrast_test.dart` asserts it.
///
/// There is deliberately **no violet in the ramp**: violet is reserved for AI
/// provenance.
@immutable
class CollectionInk {
  const CollectionInk({required this.fg, required this.bg, required this.name});

  /// Dot and label colour.
  final Color fg;

  /// Tag / chip background fill.
  final Color bg;

  /// Human-readable ramp slot name, for debugging and tests.
  final String name;

  CollectionInk copyWith({Color? fg, Color? bg, String? name}) => CollectionInk(
    fg: fg ?? this.fg,
    bg: bg ?? this.bg,
    name: name ?? this.name,
  );

  static CollectionInk lerp(CollectionInk a, CollectionInk b, double t) =>
      CollectionInk(
        fg: Color.lerp(a.fg, b.fg, t)!,
        bg: Color.lerp(a.bg, b.bg, t)!,
        name: t < 0.5 ? a.name : b.name,
      );

  /// Pairwise lerp of two full ramps. Both must be [kMemCollectionInkCount]
  /// long, which the const ramps below guarantee.
  static List<CollectionInk> lerpRamp(
    List<CollectionInk> a,
    List<CollectionInk> b,
    double t,
  ) => List<CollectionInk>.generate(
    a.length,
    (i) => CollectionInk.lerp(a[i], b[i], t),
    growable: false,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CollectionInk &&
          other.fg == fg &&
          other.bg == bg &&
          other.name == name;

  @override
  int get hashCode => Object.hash(fg, bg, name);

  @override
  String toString() => 'CollectionInk($name, fg: $fg, bg: $bg)';
}

/// The ramp is exactly this long, in both brightnesses, forever. The hash in
/// [collectionInkIndex] is taken modulo this value.
const int kMemCollectionInkCount = 8;

/// Dark ramp — index order is contractual (see [collectionInkIndex]).
const List<CollectionInk> memCollectionInksDark = <CollectionInk>[
  CollectionInk(fg: Color(0xFF6DA6FF), bg: Color(0xFF12233F), name: 'Blue'),
  CollectionInk(fg: Color(0xFF4CC9E8), bg: Color(0xFF0E2B33), name: 'Cyan'),
  CollectionInk(fg: Color(0xFF43D9A3), bg: Color(0xFF0C2E24), name: 'Teal'),
  CollectionInk(fg: Color(0xFF7ACE7A), bg: Color(0xFF14301A), name: 'Green'),
  CollectionInk(fg: Color(0xFFFFC94D), bg: Color(0xFF33270C), name: 'Amber'),
  CollectionInk(fg: Color(0xFFFF8A70), bg: Color(0xFF391B14), name: 'Coral'),
  CollectionInk(fg: Color(0xFFFF7EB6), bg: Color(0xFF38152A), name: 'Pink'),
  CollectionInk(fg: Color(0xFFA9B8C9), bg: Color(0xFF1E262F), name: 'Slate'),
];

/// Light ramp — same slot names and same index order as the dark ramp.
const List<CollectionInk> memCollectionInksLight = <CollectionInk>[
  CollectionInk(fg: Color(0xFF1E55B8), bg: Color(0xFFE3ECFC), name: 'Blue'),
  CollectionInk(fg: Color(0xFF0E6E88), bg: Color(0xFFDFF4F9), name: 'Cyan'),
  CollectionInk(fg: Color(0xFF0B7B57), bg: Color(0xFFDDF5EC), name: 'Teal'),
  CollectionInk(fg: Color(0xFF3B7A24), bg: Color(0xFFE5F4DE), name: 'Green'),
  CollectionInk(fg: Color(0xFF8A6200), bg: Color(0xFFFBF0D7), name: 'Amber'),
  CollectionInk(fg: Color(0xFFB0402A), bg: Color(0xFFFCE7E1), name: 'Coral'),
  CollectionInk(fg: Color(0xFFAD3273), bg: Color(0xFFFBE4EF), name: 'Pink'),
  CollectionInk(fg: Color(0xFF3F5259), bg: Color(0xFFDFE3E4), name: 'Slate'),
];

/// The ramp for [brightness]. Prefer [collectionInkFor] inside a widget tree —
/// this exists for tests and for code that has a brightness but no context.
List<CollectionInk> memCollectionInksFor(Brightness brightness) =>
    brightness == Brightness.dark
    ? memCollectionInksDark
    : memCollectionInksLight;

/// FNV-1a (32-bit) over the UTF-16 code units of the collection id.
///
/// Stable forever: the same id always lands on the same ink, across sessions,
/// devices, and screens. **NEVER re-hash to avoid a collision** — past 8
/// collections two collections share an ink by design, and colour is never the
/// sole signifier (every tag renders the collection title beside the dot).
int collectionInkIndex(String collectionId) {
  var hash = 0x811c9dc5;
  for (final unit in collectionId.codeUnits) {
    hash ^= unit & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
    hash ^= (unit >> 8) & 0xff;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash % kMemCollectionInkCount;
}

/// The ink for [collectionId] in the current theme's brightness.
CollectionInk collectionInkFor(BuildContext context, String collectionId) =>
    Theme.of(
      context,
    ).extension<MemSemanticColors>()!.collectionInks[collectionInkIndex(
      collectionId,
    )];
