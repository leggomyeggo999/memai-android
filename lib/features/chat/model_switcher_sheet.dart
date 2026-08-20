// The chat model switcher (§4.5 item 1, §5.5).
//
// Two pieces, deliberately in one file because they are two halves of one
// affordance:
//
//  * [ModelSwitcherPill] — the 36 dp pill under the Chat AppBar title. It
//    replaces the debug-ish `'<displayName> (<provider>)'` AppBar string while
//    keeping the active model **and** its provider visible, which the CHAT
//    SESSIONS + JOBS contract requires.
//  * [showModelSwitcherSheet] — the bottom sheet it opens: one radio row per
//    profile plus a *Manage models* row into Settings.
//
// Selecting a profile calls the **existing** `AppState.setActiveModel` path and
// nothing else. `MemChatPage`'s app listener is what then runs
// `_switchSessionProfile` (persist the OLD session, then restore the new one)
// and inserts the system row announcing the swap — so the swap is never silent
// again (`#2`). This file must not touch sessions, histories, or persistence.

import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../core/llm/chat_model_profile.dart';
import '../../theme/mem_metrics.dart';
import '../../ui/app_list_section.dart';
import '../../ui/empty_state.dart';
import '../../ui/provider_badge.dart';
import '../settings/settings_page.dart';

/// Opens the model switcher (§5.5).
///
/// Chrome (radius 20, `surfaceContainerHighest`, 60 % scrim, drag handle) comes
/// from `bottomSheetTheme`; nothing is restyled here.
Future<void> showModelSwitcherSheet(
  BuildContext context, {
  required AppState app,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext sheetContext) => _ModelSwitcherSheet(app: app),
  );
}

/// Pushes Settings focused on [section], from a navigator captured by the
/// caller.
///
/// [section] arrives as a parameter rather than a literal so this stays one
/// code path for every deep link out of the switcher.
void _pushSettings(NavigatorState navigator, SettingsSection section) {
  navigator.push(
    MaterialPageRoute<void>(
      builder: (BuildContext _) => SettingsPage(focusSection: section),
    ),
  );
}

/// The tappable model pill that lives under the Chat AppBar title.
///
/// Visual is 36 dp; the touch target is a full [MemSize.touchTarget] box around
/// it, following the same `SizedBox → Material(transparency) → InkWell` idiom
/// the shared `CollectionTag` uses, so §0.1 rule 4 holds without inflating the
/// pill itself.
class ModelSwitcherPill extends StatelessWidget {
  const ModelSwitcherPill({
    super.key,
    required this.profile,
    required this.onTap,
  });

  /// The active profile, or null when no chat model is configured.
  final ChatModelProfile? profile;

  /// Opens [showModelSwitcherSheet].
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ChatModelProfile? active = profile;
    final String label = active?.displayName ?? 'No model';

    final Widget leading = active == null
        ? Icon(
            Icons.smart_toy_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          )
        : ProviderBadge(provider: active.provider, showName: false);

    // No fixed height: the pill grows with the text scale instead of clipping.
    final Widget visual = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 36),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: MemRadius.controlAll,
          border: Border.all(
            color: scheme.outline,
            width: hairlineWidth(context),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MemSpace.x3 - 2,
            vertical: MemSpace.x2 - 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              leading,
              const SizedBox(width: MemSpace.x2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: MemSpace.x1),
              Icon(
                Icons.expand_more,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: 'Chat model',
      value: label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: MemSize.touchTarget),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: MemRadius.controlAll,
            overlayColor: memPressOverlay(scheme),
            child: Center(widthFactor: 1, child: visual),
          ),
        ),
      ),
    );
  }
}

/// The switcher sheet body.
///
/// Stateless on purpose: every row either pops the sheet or does nothing, so
/// there is no state worth holding. The profile list is read once from [app]
/// at build time — the same snapshot discipline the jobs picker uses.
class _ModelSwitcherSheet extends StatelessWidget {
  const _ModelSwitcherSheet({required this.app});

  final AppState app;

  /// Pop first, *then* mutate — the same ordering the jobs picker uses so the
  /// sheet never outlives the action it triggered.
  void _select(BuildContext sheetContext, ChatModelProfile profile) {
    Navigator.pop(sheetContext);
    if (profile.id == app.activeModelId) return;
    app.setActiveModel(profile.id);
  }

  void _manage(BuildContext sheetContext) {
    final NavigatorState navigator = Navigator.of(sheetContext);
    navigator.pop();
    _pushSettings(navigator, SettingsSection.models);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<ChatModelProfile> models = app.chatModels;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom + MemSpace.x5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              MemInsets.pageH,
              0,
              MemInsets.pageH,
              MemSpace.x3,
            ),
            child: Text('Chat model', style: theme.textTheme.titleSmall),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (models.isEmpty)
                    EmptyState(
                      icon: Icons.smart_toy_outlined,
                      headline: 'No chat models',
                      body: 'Add a model and its API key to start chatting.',
                      ctaLabel: 'Add a chat model',
                      onCta: () => _manage(context),
                    )
                  else
                    AppListSection(
                      children: <Widget>[
                        for (final ChatModelProfile p in models)
                          AppRow(
                            leading: ProviderBadge(
                              provider: p.provider,
                              showName: false,
                            ),
                            title: Text(p.displayName),
                            // The raw API model id, as §5.5 specifies — it is
                            // the only place the user can confirm exactly what
                            // is being called.
                            meta: Text(
                              p.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            selected: p.id == app.activeModelId,
                            onTap: () => _select(context, p),
                          ),
                      ],
                    ),
                  const SizedBox(height: MemSpace.x3),
                  AppListSection(
                    children: <Widget>[
                      AppRow(
                        leading: const Icon(Icons.tune),
                        title: const Text('Manage models'),
                        trailing: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onTap: () => _manage(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
