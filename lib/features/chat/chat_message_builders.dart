// Chat message rendering for §4.5 of docs/redesign/DESIGN_SPEC.md.
//
// WP-S deliverable. The verdict of the spike (docs/redesign/CHAT_RENDERING_SPIKE.md)
// is **GO on the flutter_chat_ui `Builders` API**: `chatMessageBuilder` replaces the
// library's whole per-item wrapper (alignment, padding, animation, gestures) and
// `textMessageBuilder` supplies the content, which is enough to express every row
// §4.5 asks for. Nothing in this file touches the send pipeline — it is pure
// presentation over the same `InMemoryChatController`.
//
// Two library affordances are deliberately NOT used, because using them would
// break contracts in docs/redesign/CONSTRAINTS.md:
//
//  * `Message.textStream` / `textStreamMessageBuilder` — the pipeline streams by
//    rewriting one `TextMessage` **in place under the same id**, and the persist
//    filter keys on `m is TextMessage`. Streaming state is therefore derived from
//    the text of a `TextMessage` (see [kMemChatPendingSentinel]), never from a
//    different message subtype.
//  * `Message.system` / `systemMessageBuilder` — §4.5 mandates that the persist
//    filter gain **exactly one** clause, `m.authorId != _kSystemId`. That clause is
//    only reachable if system rows are `Message.text` with an author id of
//    [kMemChatSystemAuthorId]. Use [memChatSystemMessage] to build them.
//
// Every widget here is also usable standalone (plain `ListView`), so the fallback
// path documented in the spike needs no rewrite of the row widgets.

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

// ---------------------------------------------------------------------------
// Contract constants. These mirror `mem_chat_page.dart` and must stay
// byte-identical to it — they are persistence contracts, not copy.
// ---------------------------------------------------------------------------

/// Author id for messages the user sent. Mirrors `_kUserId`.
const String kMemChatUserAuthorId = 'user';

/// Author id for model output. Mirrors `_kAssistantId`.
const String kMemChatAssistantAuthorId = 'assistant';

/// Author id for centred system rows (model switch, restore notices).
///
/// Mirrors the `_kSystemId` constant §4.5 asks `mem_chat_page.dart` to introduce.
/// Rows carrying this author are stripped by the persist filter and are never
/// added to `_openAiHist` / `_anthropicHist` / `_geminiHist`.
const String kMemChatSystemAuthorId = 'system';

/// The pending-bubble sentinel. **Byte-identical to the original** — the persist
/// filter compares against this exact string, and `streamBubble` re-displays it
/// whenever the accumulated text is still empty.
const String kMemChatPendingSentinel = '…';

/// The prefix `_failMessage` writes onto a failed pending bubble. Persisted as
/// part of the message text; only the *rendering* changes in this redesign.
const String kMemChatErrorPrefix = 'Error: ';

// Mirrors `MemMotion` (§2.11), which lives in `lib/theme/mem_metrics.dart` and is
// owned by WP-0 — that file did not exist when WP-S landed. The values are
// identical; swap these three for the real tokens once WP-0 is in.
const Duration _kMotionStandard = Duration(milliseconds: 220);
const Duration _kMotionPulse = Duration(milliseconds: 1100);
const Curve _kCurveEmphasized = Curves.easeOutCubic;
const Curve _kCurvePulse = Curves.easeInOut;

// Layout constants from §2.8 / §2.9.
const double _kPageInset = 16; // MemInsets.pageH
const double _kAssistantBodyInset = 20; // §4.5: 20 dp left inset on the block
const double _kBubbleRadius = 16;
const double _kBubbleTailRadius = 4;
const double _kBlockRadius = 12;
const double _kTouchTarget = 48; // §0.1 rule 4
const double _kUserBubbleMaxWidthFactor = 0.78; // §4.5

// ---------------------------------------------------------------------------
// Row classification
// ---------------------------------------------------------------------------

/// The five shapes a chat row can take (§4.5).
enum MemChatRowKind {
  /// Right-aligned bubble, `surfaceContainerHigh`.
  user,

  /// Full-width block on the canvas with a header row.
  assistant,

  /// Assistant block whose body is the animated three-dot pulse, i.e. the text
  /// is still [kMemChatPendingSentinel].
  assistantPending,

  /// `errorContainer` block with a retry action.
  assistantError,

  /// Centred `bodySmall` notice.
  system,
}

/// Strips the persisted [kMemChatErrorPrefix] for display.
///
/// The prefix is a storage contract; the error row renders the copy without it
/// because the row's colour and icon already say "this failed".
String memChatStripErrorPrefix(String text) {
  if (text.startsWith(kMemChatErrorPrefix)) {
    return text.substring(kMemChatErrorPrefix.length).trim();
  }
  // `_failMessage` only adds the prefix when the text does not already start with
  // 'Error', so an 'Error…' variant can reach here unprefixed.
  if (text.startsWith('Error')) return text;
  return text;
}

/// Whether [text] is the pending sentinel (leading/trailing space tolerated, the
/// same way the persist filter tolerates it).
bool memChatIsPendingSentinel(String text) =>
    text.trim() == kMemChatPendingSentinel;

/// Builds a centred system row.
///
/// System rows are `Message.text` with [kMemChatSystemAuthorId] so that the one
/// added persist-filter clause (`m.authorId != _kSystemId`) is the thing that
/// keeps them out of `ChatSessionStore`. Do not add them to provider histories.
Message memChatSystemMessage({
  required String id,
  required String text,
  DateTime? createdAt,
}) => Message.text(
  id: id,
  authorId: kMemChatSystemAuthorId,
  text: text,
  createdAt: createdAt ?? DateTime.now(),
);

// ---------------------------------------------------------------------------
// Builder configuration
// ---------------------------------------------------------------------------

/// Everything the message builders need from `MemChatPage`.
///
/// Construct it inside `build()` — it is cheap and immutable, and rebuilding it
/// is how the assistant header picks up a model switch. [memChatBuilders] returns
/// a fresh `Builders` per call; `Chat` only reassigns a field when it changes, so
/// there is no rebuild cost worth optimising.
@immutable
class MemChatBuilderConfig {
  /// Creates a configuration for [memChatBuilders].
  const MemChatBuilderConfig({
    required this.assistantLabel,
    this.userAuthorId = kMemChatUserAuthorId,
    this.systemAuthorId = kMemChatSystemAuthorId,
    this.aiGlyph,
    this.streamingMessageId,
    this.errorMessageIds = const <String>{},
    this.onRetry,
    this.onOpenMessageMenu,
    this.timeFormat,
  });

  /// Display name of the active model, shown in the assistant header row.
  /// `ChatModelProfile.displayName` — never the debug `'name (provider)'` string.
  final String assistantLabel;

  /// Author id treated as "me". Defaults to [kMemChatUserAuthorId].
  final String userAuthorId;

  /// Author id treated as a system notice. Defaults to [kMemChatSystemAuthorId].
  final String systemAuthorId;

  /// The AI-provenance sparkle for the assistant header (§2.10).
  ///
  /// Pass `const AiGlyph()` once WP-1 lands `lib/ui/ai_glyph.dart`. When null a
  /// 16 dp `Icons.auto_awesome` in `colorScheme.tertiary` is drawn instead — the
  /// same permitted AI site, just without the shared component.
  final Widget? aiGlyph;

  /// Id of the message currently receiving stream deltas, or null when idle.
  ///
  /// Set this to the pending bubble's id when the run starts and clear it in the
  /// `finally` block. It drives the 2 dp `aiAccent` caret.
  final String? streamingMessageId;

  /// Ids known to have failed this session.
  ///
  /// Optional refinement: a restored session has no such ids, so classification
  /// falls back to the `'Error'` prefix that `_failMessage` guarantees.
  final Set<String> errorMessageIds;

  /// Invoked by the error row's retry affordance. WP-7 re-sends the user message
  /// preceding [message] through the unchanged send pipeline.
  final void Function(TextMessage message)? onRetry;

  /// Invoked by a long-press on any row and by the assistant header's overflow
  /// glyph. WP-7 shows the Copy / Retry / Select text menu (§4.5, fixes `#15`).
  final void Function(BuildContext context, TextMessage message)?
  onOpenMessageMenu;

  /// Format for the assistant header timestamp. Defaults to `HH:mm`, matching the
  /// `Chat` widget's own default. Numerals are tabular via the global text theme.
  final DateFormat? timeFormat;

  /// Classifies [message] into one of the five §4.5 row shapes.
  MemChatRowKind kindOf(TextMessage message) {
    if (message.authorId == systemAuthorId) return MemChatRowKind.system;
    if (message.authorId == userAuthorId) return MemChatRowKind.user;
    if (memChatIsPendingSentinel(message.text)) {
      return MemChatRowKind.assistantPending;
    }
    if (errorMessageIds.contains(message.id) ||
        message.text.startsWith('Error')) {
      // `startsWith('Error')` is the exact test `_failMessage` itself uses when
      // deciding whether to add the prefix, so the two never disagree.
      return MemChatRowKind.assistantError;
    }
    return MemChatRowKind.assistant;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MemChatBuilderConfig &&
          other.assistantLabel == assistantLabel &&
          other.userAuthorId == userAuthorId &&
          other.systemAuthorId == systemAuthorId &&
          other.aiGlyph == aiGlyph &&
          other.streamingMessageId == streamingMessageId &&
          setEquals(other.errorMessageIds, errorMessageIds) &&
          other.onRetry == onRetry &&
          other.onOpenMessageMenu == onOpenMessageMenu &&
          other.timeFormat == timeFormat;

  @override
  int get hashCode => Object.hash(
    assistantLabel,
    userAuthorId,
    systemAuthorId,
    aiGlyph,
    streamingMessageId,
    Object.hashAllUnordered(errorMessageIds),
    onRetry,
    onOpenMessageMenu,
    timeFormat,
  );
}

/// Builds the `flutter_chat_ui` [Builders] bundle for the redesigned chat.
///
/// Wire it as:
///
/// ```dart
/// Chat(
///   chatController: _chat,
///   currentUserId: _kUserId,
///   resolveUser: _resolve,
///   onMessageSend: _handleSendFromInput,
///   theme: ChatTheme.fromThemeData(Theme.of(context)),
///   backgroundColor: Theme.of(context).colorScheme.surface,
///   builders: memChatBuilders(MemChatBuilderConfig(...)),
/// )
/// ```
///
/// Note that `onMessageLongPress` on `Chat` is **ignored** once these builders are
/// installed: the default `ChatMessage` wrapper (which reads that callback off the
/// provider tree) is replaced by [MemChatMessageWrapper]. Long-press is delivered
/// through [MemChatBuilderConfig.onOpenMessageMenu] instead.
///
/// Only [Builders.textMessageBuilder] and [Builders.chatMessageBuilder] are set
/// here. `composerBuilder`, `emptyChatListBuilder` and `chatAnimatedListBuilder`
/// are WP-7's, and can be merged with `copyWith` on the returned value.
Builders memChatBuilders(MemChatBuilderConfig config) => Builders(
  textMessageBuilder:
      (
        BuildContext context,
        TextMessage message,
        int index, {
        required bool isSentByMe,
        MessageGroupStatus? groupStatus,
      }) {
        // Deliberately routed on authorId, not `isSentByMe`: 'system' and
        // 'assistant' both report false and must render differently.
        return MemChatMessageRow(message: message, config: config);
      },
  chatMessageBuilder:
      (
        BuildContext context,
        Message message,
        int index,
        Animation<double> animation,
        Widget child, {
        bool? isRemoved,
        required bool isSentByMe,
        MessageGroupStatus? groupStatus,
      }) {
        // `groupStatus` is intentionally ignored: this design has no message
        // grouping, and the library's 300 s same-author heuristic would otherwise
        // collapse the assistant header rows.
        return MemChatMessageWrapper(
          index: index,
          animation: animation,
          child: child,
        );
      },
);

// ---------------------------------------------------------------------------
// Wrapper + router
// ---------------------------------------------------------------------------

/// Per-item wrapper: insert/remove animation plus the page gutter.
///
/// Replaces the library's `ChatMessage`, which centres the child with an `Align`
/// and a `mainAxisSize.min` `Row` — that makes a genuinely full-width assistant
/// block impossible. Here the child receives the full content width and does its
/// own alignment.
class MemChatMessageWrapper extends StatelessWidget {
  /// Creates the per-item wrapper.
  const MemChatMessageWrapper({
    super.key,
    required this.index,
    required this.animation,
    required this.child,
  });

  /// Index of the message in the controller's list.
  final int index;

  /// Insert/remove animation handed down by `SliverAnimatedList`.
  final Animation<double> animation;

  /// The row content built by [MemChatMessageRow].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `animation.drive` avoids allocating a CurvedAnimation that would need
    // disposing; SizeTransition alone (no FadeTransition) keeps the frame free of
    // a saveLayer, per the §2.11 cost budget.
    return SizeTransition(
      sizeFactor: animation.drive(CurveTween(curve: _kCurveEmphasized)),
      // Top-anchored: the row grows downwards instead of sliding out of its own
      // centre. (`axisAlignment: -1` in the pre-3.41 API.)
      alignment: AlignmentDirectional.topStart,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _kPageInset,
          index == 0 ? 8 : _kPageInset,
          _kPageInset,
          0,
        ),
        child: child,
      ),
    );
  }
}

/// Routes one [TextMessage] to the right §4.5 row widget.
///
/// Usable directly as a `ListView` item in the fallback path — it needs nothing
/// from the `flutter_chat_ui` provider tree.
class MemChatMessageRow extends StatelessWidget {
  /// Creates a router for [message].
  const MemChatMessageRow({
    super.key,
    required this.message,
    required this.config,
  });

  /// The message to render.
  final TextMessage message;

  /// Rendering configuration.
  final MemChatBuilderConfig config;

  void _openMenu(BuildContext context) =>
      config.onOpenMessageMenu?.call(context, message);

  @override
  Widget build(BuildContext context) {
    switch (config.kindOf(message)) {
      case MemChatRowKind.system:
        return MemSystemRow(text: message.text);

      case MemChatRowKind.user:
        return MemUserBubble(
          text: message.text,
          onLongPress: config.onOpenMessageMenu == null
              ? null
              : () => _openMenu(context),
        );

      case MemChatRowKind.assistantError:
        return MemErrorRow(
          text: memChatStripErrorPrefix(message.text),
          onRetry: config.onRetry == null
              ? null
              : () => config.onRetry!(message),
          onLongPress: config.onOpenMessageMenu == null
              ? null
              : () => _openMenu(context),
        );

      case MemChatRowKind.assistantPending:
        return MemAssistantBlock(
          text: '',
          label: config.assistantLabel,
          time: _formatTime(config, message),
          aiGlyph: config.aiGlyph,
          pending: true,
          // No overflow menu on a bubble that has no content to copy yet.
          onOpenMenu: null,
        );

      case MemChatRowKind.assistant:
        return MemAssistantBlock(
          text: message.text,
          label: config.assistantLabel,
          time: _formatTime(config, message),
          aiGlyph: config.aiGlyph,
          streaming: config.streamingMessageId == message.id,
          onOpenMenu: config.onOpenMessageMenu == null
              ? null
              : () => _openMenu(context),
          onLongPress: config.onOpenMessageMenu == null
              ? null
              : () => _openMenu(context),
        );
    }
  }
}

String? _formatTime(MemChatBuilderConfig config, TextMessage message) {
  final at = message.resolvedTime;
  if (at == null) return null;
  final format = config.timeFormat ?? DateFormat('HH:mm');
  return format.format(at.toLocal());
}

// ---------------------------------------------------------------------------
// Row widgets
// ---------------------------------------------------------------------------

/// A full-width assistant block: header row, then the model's prose on the
/// canvas with a 20 dp left inset (§4.5). Not a bubble — that separation is the
/// point.
///
/// Set [pending] while the message text is still [kMemChatPendingSentinel] and
/// [streaming] once deltas are arriving.
class MemAssistantBlock extends StatelessWidget {
  /// Creates an assistant block.
  const MemAssistantBlock({
    super.key,
    required this.text,
    required this.label,
    this.time,
    this.aiGlyph,
    this.pending = false,
    this.streaming = false,
    this.onOpenMenu,
    this.onLongPress,
  });

  /// The model's prose. Ignored when [pending] is true.
  final String text;

  /// Model display name shown in the header.
  final String label;

  /// Preformatted, tabular timestamp. Null hides it.
  final String? time;

  /// AI-provenance sparkle. Null draws the built-in fallback glyph.
  final Widget? aiGlyph;

  /// Renders the three-dot pulse instead of [text].
  final bool pending;

  /// Renders the 2 dp `aiAccent` caret after [text]; it fades out when this goes
  /// false, rather than disappearing on the frame the stream ends.
  final bool streaming;

  /// Opens the message context menu from the header's overflow glyph.
  final VoidCallback? onOpenMenu;

  /// Opens the same menu from a long-press on the block body.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final body = pending
        ? const Align(alignment: Alignment.centerLeft, child: MemTypingDots())
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: text),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: MemStreamingCaret(active: streaming),
                ),
              ],
            ),
            style: theme.textTheme.bodyLarge?.copyWith(color: cs.onSurface),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: _kTouchTarget,
          child: Row(
            children: [
              // 16 dp glyph + 4 dp gap = the 20 dp inset the body aligns to.
              SizedBox(
                width: _kAssistantBodyInset,
                child: Align(
                  alignment: Alignment.centerLeft,
                  // Permitted AI-provenance site (§2.10): the assistant header
                  // sparkle. `tertiary` mirrors `MemSemanticColors.aiAccent`.
                  child:
                      aiGlyph ??
                      Icon(Icons.auto_awesome, size: 16, color: cs.tertiary),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    if (time != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        time!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onOpenMenu != null)
                SizedBox(
                  width: _kTouchTarget,
                  height: _kTouchTarget,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    constraints: const BoxConstraints.tightFor(
                      width: _kTouchTarget,
                      height: _kTouchTarget,
                    ),
                    tooltip: 'Message actions',
                    color: cs.onSurfaceVariant,
                    icon: const Icon(Icons.more_horiz),
                    onPressed: onOpenMenu,
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: _kAssistantBodyInset),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: onLongPress,
            child: body,
          ),
        ),
      ],
    );
  }
}

/// A right-aligned user bubble: `surfaceContainerHigh`, radius 16 with a 4 dp
/// bottom-right corner, capped at 78 % of the content width (§4.5).
class MemUserBubble extends StatelessWidget {
  /// Creates a user bubble.
  const MemUserBubble({super.key, required this.text, this.onLongPress});

  /// The message text.
  final String text;

  /// Opens the message context menu.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth * _kUserBubbleMaxWidthFactor
            : double.infinity;
        return Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(_kBubbleRadius),
                    topRight: Radius.circular(_kBubbleRadius),
                    bottomLeft: Radius.circular(_kBubbleRadius),
                    bottomRight: Radius.circular(_kBubbleTailRadius),
                  ),
                ),
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurface,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A centred system notice: model switch, session restore (§4.5).
///
/// Build the message with [memChatSystemMessage] so it carries the author id the
/// persist filter excludes.
class MemSystemRow extends StatelessWidget {
  /// Creates a system row.
  const MemSystemRow({super.key, required this.text});

  /// The notice copy, e.g. "Switched to Claude Sonnet — conversation restored
  /// from Aug 15".
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A failed turn: an `errorContainer` block with recovery copy and a retry
/// action (§4.5). Never rendered as assistant prose.
///
/// [text] should already be human copy — `memErrorText()` output, or the
/// persisted message with [memChatStripErrorPrefix] applied. Raw exception text
/// must never reach here (§0.1 rule 2).
class MemErrorRow extends StatelessWidget {
  /// Creates an error row.
  const MemErrorRow({
    super.key,
    required this.text,
    this.onRetry,
    this.onLongPress,
  });

  /// Human-readable failure copy.
  final String text;

  /// Re-sends the preceding user message. Null hides the retry affordance.
  final VoidCallback? onRetry;

  /// Opens the message context menu.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPress: onLongPress,
      child: Container(
        padding: EdgeInsets.fromLTRB(14, 12, onRetry == null ? 14 : 4, 12),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(_kBlockRadius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 20, color: cs.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onErrorContainer,
                ),
              ),
            ),
            if (onRetry != null)
              SizedBox(
                width: _kTouchTarget,
                height: _kTouchTarget,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 20,
                  constraints: const BoxConstraints.tightFor(
                    width: _kTouchTarget,
                    height: _kTouchTarget,
                  ),
                  tooltip: 'Retry',
                  color: cs.onErrorContainer,
                  icon: const Icon(Icons.refresh),
                  onPressed: onRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Streaming affordances
// ---------------------------------------------------------------------------

/// The three-dot pulse shown while the pending bubble still holds
/// [kMemChatPendingSentinel].
///
/// Animated by tweening the dot **colour alpha**, not by wrapping anything in an
/// `Opacity` — no `saveLayer`, per the §2.11 cost budget. Drawn in
/// `onSurfaceVariant` rather than `aiAccent`: §2.10 reserves violet for the header
/// sparkle and the streaming caret, and a mechanical `tertiary` audit would flag
/// anything else in this file.
class MemTypingDots extends StatefulWidget {
  /// Creates the pulse.
  const MemTypingDots({super.key, this.dotSize = 6, this.gap = 4});

  /// Diameter of each dot.
  final double dotSize;

  /// Space between dots.
  final double gap;

  @override
  State<MemTypingDots> createState() => _MemTypingDotsState();
}

class _MemTypingDotsState extends State<MemTypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _kMotionPulse)
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      // Keeps the pending row the same height as one line of bodyLarge (16/26),
      // so the block does not jump when the first token lands.
      height: 26,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(3, (i) {
              final start = i * 0.2;
              final t = _kCurvePulse.transform(
                ((_controller.value - start) / 0.6).clamp(0.0, 1.0),
              );
              return Padding(
                padding: EdgeInsets.only(right: i == 2 ? 0 : widget.gap),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    // §2.11 skeleton pulse: 0.55 → 1.0.
                    color: base.withValues(alpha: 0.55 + 0.45 * t),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

/// The 2 dp `aiAccent` caret that trails streaming text and fades on completion
/// (§4.5).
///
/// Always mount it; toggle [active]. When it goes false the bar animates to zero
/// width and transparent over `MemMotion.standard`, which is what "fades on
/// completion" means — a caret that vanishes on the last frame reads as a glitch.
class MemStreamingCaret extends StatelessWidget {
  /// Creates a caret.
  const MemStreamingCaret({super.key, required this.active, this.height = 18});

  /// Whether tokens are still arriving for this message.
  final bool active;

  /// Height of the caret bar; roughly the cap height of `bodyLarge`.
  final double height;

  @override
  Widget build(BuildContext context) {
    // Permitted AI-provenance site (§2.10): the streaming caret.
    final color = Theme.of(context).colorScheme.tertiary;
    return AnimatedContainer(
      duration: _kMotionStandard,
      curve: _kCurveEmphasized,
      margin: EdgeInsets.only(left: active ? 3 : 0),
      width: active ? 2 : 0,
      height: height,
      decoration: BoxDecoration(
        color: active ? color : color.withValues(alpha: 0),
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
