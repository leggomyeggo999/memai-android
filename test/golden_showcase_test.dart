// Renders the "Midnight Instrument" redesign to reviewable PNGs.
//
// There is no Android device, no emulator, and no windows/ or web/ platform
// folder in this repo, so the app cannot be launched. These goldens are the only
// way to *see* the redesign. Every surface below is composed from the real
// widgets in `lib/ui/`, `lib/theme/` and `lib/features/chat/` with fake data —
// nothing is reimplemented, and nothing touches the network.
//
// Regenerate with:
//   flutter test test/golden_showcase_test.dart --update-goldens
//
// Fonts: see `test/support/golden_harness.dart`. Without it every glyph would be
// a filled box and these images would be useless.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:memai_android/core/mem/mem_api_exception.dart';
import 'package:memai_android/features/chat/chat_message_builders.dart';
import 'package:memai_android/theme/mem_app_theme.dart';
import 'package:memai_android/theme/mem_collection_ink.dart';
import 'package:memai_android/theme/mem_metrics.dart';
import 'package:memai_android/theme/mem_semantic_colors.dart';
import 'package:memai_android/ui/ai_glyph.dart';
import 'package:memai_android/ui/app_list_section.dart';
import 'package:memai_android/ui/chip_strip.dart';
import 'package:memai_android/ui/collection_tag.dart';
import 'package:memai_android/ui/confirm_destructive_dialog.dart';
import 'package:memai_android/ui/date_labels.dart';
import 'package:memai_android/ui/editor_sheet.dart';
import 'package:memai_android/ui/empty_state.dart';
import 'package:memai_android/ui/error_state.dart';
import 'package:memai_android/ui/hairline.dart';
import 'package:memai_android/ui/inline_spinner.dart';
import 'package:memai_android/ui/provider_badge.dart';
import 'package:memai_android/ui/search_pill.dart';
import 'package:memai_android/ui/section_header.dart';
import 'package:memai_android/ui/skeleton.dart';
import 'package:memai_android/ui/status_tile.dart';
import 'package:memai_android/ui/sticky_action_bar.dart';

import 'support/golden_harness.dart';

// ---------------------------------------------------------------------------
// Fake data
// ---------------------------------------------------------------------------

/// One collection id per ink slot, found by running the **real**
/// [collectionInkIndex] hash rather than by hard-coding indices — so the
/// showcase provably covers all eight slots of the shipped ramp.
final List<String> _inkSlotIds = () {
  final List<String?> out = List<String?>.filled(kMemCollectionInkCount, null);
  int found = 0;
  for (int i = 0; found < kMemCollectionInkCount && i < 100000; i++) {
    final String id = 'collection-$i';
    final int slot = collectionInkIndex(id);
    if (out[slot] == null) {
      out[slot] = id;
      found++;
    }
  }
  return out.map((String? e) => e!).toList(growable: false);
}();

/// Ramp slot names, straight off the dark ramp (both ramps share slot names).
const List<String> _inkSlotNames = <String>[
  'Blue',
  'Cyan',
  'Teal',
  'Green',
  'Amber',
  'Coral',
  'Pink',
  'Slate',
];

class _FakeNote {
  const _FakeNote({
    required this.title,
    required this.snippet,
    required this.collectionIds,
    required this.updatedAt,
  });

  final String title;
  final String snippet;
  final List<String> collectionIds;
  final DateTime updatedAt;
}

/// Two day-groups of notes, pinned to [kMemGoldenNow] so the relative times and
/// day labels are identical on every run.
final List<_FakeNote> _fakeNotes = <_FakeNote>[
  _FakeNote(
    title: 'Midnight Instrument — colour constitution',
    snippet:
        'Elevation is zero app-wide. Depth is a surface step plus a 1 dp '
        'hairline; violet is reserved for AI provenance and nothing else.',
    collectionIds: <String>[_inkSlotIds[0]],
    updatedAt: kMemGoldenNow.subtract(const Duration(minutes: 4)),
  ),
  _FakeNote(
    title: 'Sync retry backoff — decision log',
    snippet:
        'Settled on jittered exponential backoff capped at 30 s. The old fixed '
        '5 s retry was hammering the API during airplane-mode flaps.',
    collectionIds: <String>[_inkSlotIds[2], _inkSlotIds[4]],
    updatedAt: kMemGoldenNow.subtract(const Duration(hours: 2)),
  ),
  _FakeNote(
    title: 'Groceries',
    snippet: 'Oat milk, sourdough starter, the good olive oil, cardamom pods.',
    collectionIds: <String>[_inkSlotIds[3], _inkSlotIds[6], _inkSlotIds[1]],
    updatedAt: kMemGoldenNow.subtract(const Duration(hours: 6)),
  ),
  _FakeNote(
    title: 'Call notes — Priya, platform review',
    snippet:
        'She wants the migration plan split by surface, not by team. Follow up '
        'with a one-pager before Thursday.',
    collectionIds: <String>[_inkSlotIds[5]],
    updatedAt: kMemGoldenNow.subtract(const Duration(days: 1, hours: 3)),
  ),
  _FakeNote(
    title: 'A note with no collections and a title long enough to ellipsize',
    snippet: 'Single-line snippet.',
    collectionIds: <String>[],
    updatedAt: kMemGoldenNow.subtract(const Duration(days: 1, hours: 7)),
  ),
  _FakeNote(
    title: 'Reading — "The Timeless Way of Building"',
    snippet:
        'Pattern languages as a design grammar. Relevant to the component '
        'inventory work.',
    collectionIds: <String>[_inkSlotIds[7], _inkSlotIds[0]],
    updatedAt: kMemGoldenNow.subtract(const Duration(days: 1, hours: 11)),
  ),
];

const Map<int, String> _collectionTitles = <int, String>{
  0: 'Design system',
  1: 'Kitchen',
  2: 'Engineering',
  3: 'Groceries',
  4: 'Decisions',
  5: 'Meetings',
  6: 'Household',
  7: 'Reading list',
};

String _titleForCollection(String id) {
  final int slot = _inkSlotIds.indexOf(id);
  return _collectionTitles[slot] ?? id;
}

// ---------------------------------------------------------------------------
// Surfaces
// ---------------------------------------------------------------------------

/// Every shared component in `lib/ui/` on one scrollable surface.
class DesignSystemShowcase extends StatefulWidget {
  const DesignSystemShowcase({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<DesignSystemShowcase> createState() => _DesignSystemShowcaseState();
}

class _DesignSystemShowcaseState extends State<DesignSystemShowcase> {
  final TextEditingController _search = TextEditingController(text: 'backoff');
  final TextEditingController _field = TextEditingController(
    text: 'mem_live_9f2c…',
  );
  final TextEditingController _errorField = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _field.dispose();
    _errorField.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final MemSemanticColors sem = memSemanticColorsOf(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Design system'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        controller: widget.controller,
        padding: const EdgeInsets.only(bottom: MemInsets.listBottomForNav),
        children: <Widget>[
          // ---- Sections & rows ------------------------------------------
          const SectionHeader(label: 'List section · rows'),
          AppListSection(
            children: <Widget>[
              AppRow(
                leading: CollectionTag(
                  collectionId: _inkSlotIds[0],
                  title: 'Design system',
                  variant: CollectionTagVariant.dot,
                ),
                title: const Text('Row with a leading ink dot'),
                subtitle: const Text(
                  'bodyMedium onSurfaceVariant, two lines max, then ellipsis. '
                  'The whole row is the tap target.',
                ),
                trailingText: '4m',
                onTap: () {},
              ),
              AppRow(
                title: const Text('Row with meta tags and a trailing control'),
                subtitle: const Text('Secondary line.'),
                meta: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(
                      child: CollectionTag(
                        collectionId: _inkSlotIds[2],
                        title: 'Engineering',
                      ),
                    ),
                    const SizedBox(width: MemSpace.chipGap),
                    const CollectionOverflowTag(count: 3),
                  ],
                ),
                trailing: IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {},
                ),
                trailingText: '2h',
                onTap: () {},
              ),
              AppRow(
                title: const Text('Selected row'),
                subtitle: const Text('2 dp primary bar + 16 dp check glyph.'),
                selected: true,
                onTap: () {},
              ),
              const AppRow(
                title: Text('Disabled row'),
                subtitle: Text('Reduced emphasis via colour tokens only.'),
                enabled: false,
              ),
            ],
          ),

          // ---- Collection ink -------------------------------------------
          const SectionHeader(label: 'Collection ink · all 8 slots'),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: Wrap(
              spacing: MemSpace.chipGap,
              runSpacing: MemSpace.x1,
              children: <Widget>[
                for (int i = 0; i < kMemCollectionInkCount; i++)
                  CollectionTag(
                    collectionId: _inkSlotIds[i],
                    title: '${i + 1} ${_inkSlotNames[i]}',
                  ),
              ],
            ),
          ),
          const SizedBox(height: MemSpace.x3),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: Row(
              children: <Widget>[
                CollectionTag(
                  collectionId: _inkSlotIds[0],
                  title: 'Dot',
                  variant: CollectionTagVariant.dot,
                ),
                const SizedBox(width: MemSpace.x3),
                Text(
                  'dot variant (title lives beside it)',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          // ---- ChipStrip -------------------------------------------------
          const SectionHeader(label: 'Chip strip · chip variant'),
          ChipStrip(
            leadingPinned: ActionChip(label: const Text('All'), onPressed: () {}),
            trailingAction: IconButton(
              tooltip: 'Manage collections',
              icon: const Icon(Icons.tune),
              onPressed: () {},
            ),
            children: <Widget>[
              for (int i = 0; i < kMemCollectionInkCount; i++)
                CollectionTag(
                  collectionId: _inkSlotIds[i],
                  title: _collectionTitles[i]!,
                  variant: CollectionTagVariant.chip,
                  count: 3 + i * 4,
                  selected: i == 2,
                  onTap: () {},
                ),
            ],
          ),

          // ---- Search pill ----------------------------------------------
          const SectionHeader(label: 'Search pill'),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: SearchPill(hint: 'Search notes', onTap: () {}),
          ),
          const SizedBox(height: MemSpace.x2),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: SearchPill(
              hint: 'Search notes',
              active: true,
              controller: _search,
              onTap: () {},
              onClear: () {},
              onCancel: () {},
            ),
          ),

          // ---- Status tiles ----------------------------------------------
          const SectionHeader(label: 'Status tiles · all levels'),
          AppListSection(
            children: <Widget>[
              StatusTile(
                icon: Icons.vpn_key_outlined,
                label: 'Mem API key',
                level: StatusLevel.ok,
                status: 'Key saved · ${memMaskedSecret('mem_live_9f24F2')}',
                actionLabel: 'Change',
                onAction: () {},
              ),
              StatusTile(
                icon: Icons.link,
                label: 'MCP connection',
                level: StatusLevel.pending,
                status: 'Waiting for browser…',
                busy: true,
                actionLabel: 'Connect',
                onAction: () {},
              ),
              const StatusTile(
                icon: Icons.update,
                label: 'Model catalog',
                level: StatusLevel.attention,
                status: 'Drifted',
                detail: '2 saved models are no longer offered.',
              ),
              StatusTile(
                icon: Icons.mic_none,
                label: 'Voice transcription',
                level: StatusLevel.error,
                status: 'Key rejected',
                actionLabel: 'Fix',
                onAction: () {},
              ),
              const StatusTile(
                icon: Icons.widgets_outlined,
                label: 'Home widget',
                level: StatusLevel.neutral,
                status: 'Not set',
              ),
            ],
          ),

          // ---- Buttons ----------------------------------------------------
          const SectionHeader(label: 'Buttons'),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: Wrap(
              spacing: MemSpace.x3,
              runSpacing: MemSpace.x2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                FilledButton.tonal(
                  onPressed: () {},
                  child: const Text('Tonal'),
                ),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                const FilledButton(
                  onPressed: null,
                  child: Text('Disabled'),
                ),
                IconButton(
                  tooltip: 'Icon button',
                  icon: const Icon(Icons.bookmark_border),
                  onPressed: () {},
                ),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const InlineSpinner(size: 16, color: Colors.white),
                  label: const Text('Saving'),
                ),
              ],
            ),
          ),

          // ---- Inputs ------------------------------------------------------
          const SectionHeader(label: 'Text fields · global InputDecorationTheme'),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextField(
                  controller: _field,
                  decoration: const InputDecoration(
                    labelText: 'Mem API key',
                    hintText: 'mem_live_…',
                    helperText: 'Stored in the device keystore, never synced.',
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                ),
                const SizedBox(height: MemSpace.x4),
                TextField(
                  controller: _errorField,
                  decoration: const InputDecoration(
                    labelText: 'Collection title',
                    hintText: 'e.g. Reading list',
                    errorText: 'Title cannot be empty.',
                  ),
                ),
              ],
            ),
          ),

          // ---- AI provenance + provider badges -----------------------------
          const SectionHeader(label: 'AI provenance · provider badges'),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: Wrap(
              spacing: MemSpace.x4,
              runSpacing: MemSpace.x3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const AiGlyph(),
                const AiGlyph(size: 16),
                const AiGlyph(size: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: MemSpace.x3,
                    vertical: MemSpace.x2,
                  ),
                  decoration: BoxDecoration(
                    color: sem.aiContainer,
                    borderRadius: MemRadius.controlAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const AiGlyph(size: 16),
                      const SizedBox(width: MemSpace.x2),
                      Text(
                        'Processing in Mem…',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: sem.onAiContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const ProviderBadge(provider: 'openai'),
                const ProviderBadge(provider: 'anthropic'),
                const ProviderBadge(provider: 'gemini'),
              ],
            ),
          ),

          // ---- Progress ----------------------------------------------------
          const SectionHeader(label: 'Inline spinner · hairline'),
          Padding(
            padding: MemSpace.pageHorizontal,
            child: Row(
              children: <Widget>[
                const InlineSpinner(),
                const SizedBox(width: MemSpace.x4),
                const InlineSpinner(size: 24),
                const SizedBox(width: MemSpace.x4),
                Text(
                  '16 dp in pills, 24 dp in list footers',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MemSpace.x4),
          const Hairline(indent: MemInsets.pageH, endIndent: MemInsets.pageH),

          // ---- Skeleton ----------------------------------------------------
          const SectionHeader(label: 'Skeleton list'),
          const SkeletonList(rowCount: 3),

          // ---- Empty / error -----------------------------------------------
          const SectionHeader(label: 'Empty state'),
          SizedBox(
            height: 300,
            child: EmptyState(
              icon: Icons.note_add_outlined,
              headline: 'No notes yet',
              body: 'Capture a thought and it will show up here.',
              ctaLabel: 'Capture a note',
              onCta: () {},
            ),
          ),
          const SectionHeader(label: 'Error state'),
          SizedBox(
            height: 320,
            child: ErrorState(
              error: MemApiException(
                'Your Mem API key was rejected. Add a current key in Settings.',
                statusCode: 401,
              ),
              onRetry: () {},
            ),
          ),

          // ---- Sticky action bar --------------------------------------------
          const SectionHeader(label: 'Sticky action bar'),
          StickyActionBar(
            caption: 'Draft saved locally · 2 attachments',
            secondary: OutlinedButton(
              onPressed: () {},
              child: const Text('Discard'),
            ),
            primary: FilledButton(
              onPressed: () {},
              child: const Text('Save to Mem'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Notes tab chrome, reused by the timeline / empty / error / loading
/// goldens so the four read as the same screen in four states.
class NotesShellShowcase extends StatelessWidget {
  const NotesShellShowcase({super.key, required this.body, this.chips = true});

  final Widget body;
  final bool chips;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MemInsets.pageH,
              0,
              MemInsets.pageH,
              MemSpace.x1,
            ),
            child: SearchPill(hint: 'Search notes', onTap: () {}),
          ),
          if (chips)
            ChipStrip(
              leadingPinned: ActionChip(
                label: const Text('All'),
                onPressed: () {},
              ),
              trailingAction: IconButton(
                tooltip: 'Manage collections',
                icon: const Icon(Icons.tune),
                onPressed: () {},
              ),
              children: <Widget>[
                for (int i = 0; i < kMemCollectionInkCount; i++)
                  CollectionTag(
                    collectionId: _inkSlotIds[i],
                    title: _collectionTitles[i]!,
                    variant: CollectionTagVariant.chip,
                    count: 3 + i * 4,
                    selected: false,
                    onTap: () {},
                  ),
              ],
            ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: const _ShellNavBarMock(selected: 0),
    );
  }
}

/// A visual stand-in for `MemShell`'s bottom bar so the goldens show the whole
/// screen budget. The shell itself cannot be pumped headlessly with its real
/// tabs (they hydrate from the secure vault), and `test/shell_smoke_test.dart`
/// is what asserts the real one.
class _ShellNavBarMock extends StatelessWidget {
  const _ShellNavBarMock({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: scheme.outline,
            width: hairlineWidth(context),
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (_) {},
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: 'Notes',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle),
            label: 'Capture',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
        ],
      ),
    );
  }
}

/// The Notes timeline: one [AppListSection] per day group, headed by a
/// sentence-case [memDayLabel] — the same composition `notes_page.dart` uses.
class NotesTimelineShowcase extends StatelessWidget {
  const NotesTimelineShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final Map<String, List<_FakeNote>> groups = <String, List<_FakeNote>>{};
    for (final _FakeNote n in _fakeNotes) {
      final String key = DateFormat.yMMMEd().format(n.updatedAt);
      groups.putIfAbsent(key, () => <_FakeNote>[]).add(n);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: MemInsets.listBottomForNav),
      children: <Widget>[
        for (final MapEntry<String, List<_FakeNote>> g in groups.entries)
          AppListSection(
            header: SectionHeader(
              label: memDayLabel(g.value.first.updatedAt, now: kMemGoldenNow),
              uppercase: false,
              padding: const EdgeInsets.only(top: MemSpace.sectionGap),
            ),
            children: <Widget>[
              for (final _FakeNote n in g.value) _NoteRowShowcase(note: n),
            ],
          ),
      ],
    );
  }
}

class _NoteRowShowcase extends StatelessWidget {
  const _NoteRowShowcase({required this.note});

  final _FakeNote note;

  @override
  Widget build(BuildContext context) {
    return AppRow(
      minHeight: MemSize.rowNote,
      onTap: () {},
      title: Text(note.title),
      subtitle: Text(note.snippet),
      meta: note.collectionIds.isEmpty
          ? null
          : _NoteTagsShowcase(ids: note.collectionIds),
      trailingText: memRelativeTime(note.updatedAt, now: kMemGoldenNow),
    );
  }
}

/// Mirrors `notes_page.dart`'s `_NoteTags`: at most two ink tags, then `+n`,
/// collapsing entirely once [AppRowDensityScope] reports `condensed`.
class _NoteTagsShowcase extends StatelessWidget {
  const _NoteTagsShowcase({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    if (AppRowDensityScope.of(context).collapseTags) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: CollectionOverflowTag(count: ids.length),
      );
    }
    final List<String> shown = ids.take(2).toList(growable: false);
    final int hidden = ids.length - shown.length;
    final List<Widget> children = <Widget>[];
    for (final String id in shown) {
      if (children.isNotEmpty) {
        children.add(const SizedBox(width: MemSpace.chipGap));
      }
      children.add(
        Flexible(
          child: CollectionTag(
            collectionId: id,
            title: _titleForCollection(id),
          ),
        ),
      );
    }
    if (hidden > 0) {
      children
        ..add(const SizedBox(width: MemSpace.chipGap))
        ..add(CollectionOverflowTag(count: hidden));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

// ---------------------------------------------------------------------------
// Chat transcript
// ---------------------------------------------------------------------------

TextMessage _textMessage({
  required String id,
  required String authorId,
  required String text,
  required DateTime at,
}) =>
    Message.text(id: id, authorId: authorId, text: text, createdAt: at)
        as TextMessage;

/// A simulated transcript built from the real `chat_message_builders.dart`
/// widgets, routed through the real [MemChatMessageRow] / [MemChatBuilderConfig]
/// so the classification logic is exercised, not bypassed.
class ChatTranscriptShowcase extends StatelessWidget {
  const ChatTranscriptShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final MemChatBuilderConfig config = MemChatBuilderConfig(
      assistantLabel: 'Claude Sonnet 4.6',
      aiGlyph: const AiGlyph(size: 16),
      streamingMessageId: 'a-2',
      onRetry: (TextMessage _) {},
      onOpenMessageMenu: (BuildContext _, TextMessage _) {},
      timeFormat: DateFormat('HH:mm'),
    );

    final List<TextMessage> messages = <TextMessage>[
      memChatSystemMessage(
        id: 's-1',
        text: 'Switched to Claude Sonnet 4.6 — conversation restored from Mar 3',
        createdAt: kMemGoldenNow.subtract(const Duration(minutes: 12)),
      ) as TextMessage,
      _textMessage(
        id: 'u-1',
        authorId: kMemChatUserAuthorId,
        text: 'What did I decide about the sync retry backoff?',
        at: kMemGoldenNow.subtract(const Duration(minutes: 11)),
      ),
      _textMessage(
        id: 'a-1',
        authorId: kMemChatAssistantAuthorId,
        text:
            'Your decision log from 4 March says jittered exponential backoff, '
            'capped at 30 seconds. The previous fixed 5 s retry was hammering '
            'the API during airplane-mode flaps, so the cap is the point — the '
            'jitter only stops the herd from resynchronising.',
        at: kMemGoldenNow.subtract(const Duration(minutes: 11)),
      ),
      _textMessage(
        id: 'u-2',
        authorId: kMemChatUserAuthorId,
        text: 'Add that to the Engineering collection.',
        at: kMemGoldenNow.subtract(const Duration(minutes: 3)),
      ),
      _textMessage(
        id: 'a-2',
        authorId: kMemChatAssistantAuthorId,
        text: 'Filed it under Engineering and linked the original decision log',
        at: kMemGoldenNow.subtract(const Duration(minutes: 3)),
      ),
      _textMessage(
        id: 'a-3',
        authorId: kMemChatAssistantAuthorId,
        text: kMemChatPendingSentinel,
        at: kMemGoldenNow.subtract(const Duration(seconds: 20)),
      ),
      _textMessage(
        id: 'a-4',
        authorId: kMemChatAssistantAuthorId,
        text:
            '${kMemChatErrorPrefix}The model provider timed out after 90 s. '
            'Your message was not sent.',
        at: kMemGoldenNow.subtract(const Duration(seconds: 5)),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            const Flexible(
              child: Text('Claude Sonnet 4.6', overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: MemSpace.x3),
            const ProviderBadge(provider: 'anthropic'),
          ],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: MemSpace.x4),
        children: <Widget>[
          for (int i = 0; i < messages.length; i++)
            MemChatMessageWrapper(
              index: i,
              animation: kAlwaysCompleteAnimation,
              child: MemChatMessageRow(message: messages[i], config: config),
            ),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MemInsets.pageH,
              MemSpace.x2,
              MemInsets.pageH,
              MemSpace.x2,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Ask about your notes',
                      suffixIcon: Icon(
                        Icons.mic_none,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: MemSpace.x2),
                IconButton.filled(
                  tooltip: 'Send',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: () {},
                ),
              ],
            ),
          ),
          const _ShellNavBarMock(selected: 2),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// How many phone screens the design-system surface is captured as. The test
/// asserts the surface still fits in this many, so growing it fails loudly
/// instead of silently hiding a component.
const int _kShowcasePages = 5;

void main() {
  setUpAll(loadMemGoldenFonts);

  // Guards the spinner pose the goldens are captured at.
  //
  // `InlineSpinner`'s `CircularProgressIndicator` is indeterminate, so its arc
  // length is a function of its controller phase — and near the ends of the
  // 1333 ms sweep the arc collapses to a ~2 px dash that reads as a broken
  // component in a review image. `memGoldenTheme` parks every spinner at
  // [kMemGoldenSpinnerPhase]; this recomputes the arc from the SDK's own curves
  // so a Flutter bump that changes them fails here, with an explanation, rather
  // than quietly shipping specks again.
  test('golden spinner phase is a wide, legible arc', () {
    final double s = const SawTooth(
      kMemGoldenSpinnerPathCount,
    ).transform(kMemGoldenSpinnerPhase);
    final double head = const Interval(
      0.0,
      0.5,
      curve: Curves.fastOutSlowIn,
    ).transform(s);
    final double tail = const Interval(
      0.5,
      1.0,
      curve: Curves.fastOutSlowIn,
    ).transform(s);
    // `_CircularProgressIndicatorPainter`: arcSweep = (head - tail) * 3/2 * pi.
    final double sweepDegrees = (head - tail) * 270.0;
    expect(
      sweepDegrees,
      greaterThan(260.0),
      reason:
          'the harness spinner phase no longer lands on a near-maximal arc; '
          'recheck _strokeHeadTween/_strokeTailTween in the SDK',
    );

    // …and that the phase is actually wired into the themes the goldens use.
    for (final (_, bool dark) in kMemGoldenThemes) {
      final AnimationController? c = memGoldenTheme(
        dark ? memDarkTheme : memLightTheme,
      ).progressIndicatorTheme.controller;
      expect(c, isNotNull);
      expect(c!.value, kMemGoldenSpinnerPhase);
      expect(c.isAnimating, isFalse);
    }
  });

  for (final (String themeName, bool dark) in kMemGoldenThemes) {
    final ThemeData theme = dark ? memDarkTheme : memLightTheme;

    group(themeName, () {
      testWidgets('design system showcase', (WidgetTester tester) async {
        final ScrollController controller = ScrollController();
        addTearDown(controller.dispose);

        await pumpMemGolden(
          tester,
          theme: theme,
          child: DesignSystemShowcase(controller: controller),
        );

        // One scrollable surface, captured as `_kShowcasePages` phone screens
        // that together cover it end to end.
        final double max = await resolveMaxScrollExtent(tester, controller);
        expect(
          max,
          lessThanOrEqualTo(
            kMemGoldenLogicalSize.height * (_kShowcasePages - 1),
          ),
          reason:
              'the showcase grew past $_kShowcasePages screens — add pages or '
              'the middle of it will not appear in any golden',
        );
        for (int page = 0; page < _kShowcasePages; page++) {
          controller.jumpTo(max * page / (_kShowcasePages - 1));
          await settleMemGolden(tester);
          await expectMemGolden(
            tester,
            '${themeName}_design_system_p${page + 1}',
          );
        }
      });

      testWidgets('notes timeline', (WidgetTester tester) async {
        await pumpMemGolden(
          tester,
          theme: theme,
          child: const NotesShellShowcase(body: NotesTimelineShowcase()),
        );
        await expectMemGolden(tester, '${themeName}_notes_timeline');
      });

      testWidgets('notes empty state', (WidgetTester tester) async {
        await pumpMemGolden(
          tester,
          theme: theme,
          child: NotesShellShowcase(
            body: EmptyState(
              firstRun: true,
              icon: Icons.note_add_outlined,
              headline: 'Nothing captured yet',
              body: 'Your Mem notes will appear here the moment you add one.',
              ctaLabel: 'Capture a note',
              onCta: () {},
            ),
          ),
        );
        await expectMemGolden(tester, '${themeName}_notes_empty');
      });

      testWidgets('notes error state', (WidgetTester tester) async {
        await pumpMemGolden(
          tester,
          theme: theme,
          child: NotesShellShowcase(
            body: ErrorState(
              error: MemApiException(
                'Your Mem API key was rejected. Add a current key in Settings.',
                statusCode: 401,
              ),
              onRetry: () {},
            ),
          ),
        );
        await expectMemGolden(tester, '${themeName}_notes_error');
      });

      testWidgets('notes loading skeleton', (WidgetTester tester) async {
        await pumpMemGolden(
          tester,
          theme: theme,
          child: const NotesShellShowcase(
            body: SingleChildScrollView(
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(vertical: MemSpace.x4),
              child: SkeletonList(rowCount: 8),
            ),
          ),
        );
        await expectMemGolden(tester, '${themeName}_notes_skeleton');
      });

      testWidgets('chat transcript', (WidgetTester tester) async {
        await pumpMemGolden(
          tester,
          theme: theme,
          child: const ChatTranscriptShowcase(),
        );
        await expectMemGolden(tester, '${themeName}_chat_transcript');
      });

      testWidgets('destructive confirm dialog', (WidgetTester tester) async {
        await pumpMemGolden(
          tester,
          theme: theme,
          child: const NotesShellShowcase(body: NotesTimelineShowcase()),
        );

        final BuildContext ctx = tester.element(
          find.byType(NotesTimelineShowcase),
        );
        // Not awaited: the dialog is popped below, once the frame is captured.
        unawaited(
          confirmDestructive(
            ctx,
            title: 'Move this note to trash?',
            consequence:
                'It leaves your timeline immediately. You can restore it from '
                'Trash for 30 days.',
            actionLabel: 'Move to trash',
          ),
        );
        await settleMemGolden(tester);
        await expectMemGolden(tester, '${themeName}_confirm_dialog');

        Navigator.of(ctx).pop(false);
        await settleMemGolden(tester);
      });

      testWidgets('editor sheet', (WidgetTester tester) async {
        final TextEditingController title = TextEditingController(
          text: 'Reading list',
        );
        final TextEditingController description = TextEditingController(
          text: 'Long-form articles worth a second pass.',
        );
        addTearDown(title.dispose);
        addTearDown(description.dispose);

        await pumpMemGolden(
          tester,
          theme: theme,
          child: const NotesShellShowcase(body: NotesTimelineShowcase()),
        );

        final BuildContext ctx = tester.element(
          find.byType(NotesTimelineShowcase),
        );
        unawaited(
          showEditorSheet<void>(
            context: ctx,
            title: 'Edit collection',
            isValid: () => title.text.trim().isNotEmpty,
            onSave: (BuildContext _) async {},
            footerNote: const Text(
              'Collections sync to every device signed in to Mem.',
            ),
            fieldsBuilder: (BuildContext _, EditorSheetState state) =>
                <Widget>[
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Reading list',
                ),
                onChanged: (_) => state.refresh(),
              ),
              const SizedBox(height: MemSpace.x4),
              TextField(
                controller: description,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  helperText: 'Optional. Shown under the collection name.',
                ),
                onChanged: (_) => state.refresh(),
              ),
            ],
          ),
        );
        await settleMemGolden(tester);
        await expectMemGolden(tester, '${themeName}_editor_sheet');

        Navigator.of(ctx).pop();
        await settleMemGolden(tester);
      });
    });
  }
}
