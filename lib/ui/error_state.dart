import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../core/mem/mem_api_client.dart';
import '../core/mem/mem_api_exception.dart';
import '../features/settings/settings_page.dart';
import '../theme/mem_metrics.dart';

/// What the user sees when we have nothing better to tell them.
const String kMemGenericErrorText = 'Something went wrong. Please try again.';

/// The **only** way an error becomes user-visible (§3.6, rule 2 of §0.1).
///
/// Routes:
/// * [DioException] → `MemApiClient.formatError` — the purpose-built formatter
///   that digs `error_metadata.message` / `error_description` out of a Mem API
///   response body and falls back to the transport message.
/// * [MemApiException] → its `message` (already written for humans).
/// * anything else → [kMemGenericErrorText].
///
/// **A raw `e.toString()` must never reach a widget.** The raw string still
/// goes to telemetry: callers that own a `MemErrorReporter` context string
/// ('notes_load', 'chat', 'prompt_job') keep reporting it themselves — this
/// function is the presentation half only, and deliberately does not report,
/// so it cannot double-count.
String memErrorText(Object error) {
  if (error is DioException) return MemApiClient.formatError(error);
  if (error is MemApiException) return error.message;
  return kMemGenericErrorText;
}

/// HTTP status behind an error, when there is one.
int? memErrorStatusCode(Object error) {
  if (error is DioException) return error.response?.statusCode;
  if (error is MemApiException) return error.statusCode;
  return null;
}

/// True for the failures a user can only fix in Settings — a rejected or
/// missing API key. Drives the automatic "Open Settings" action on [errSnack].
bool memErrorIsAuth(Object error) {
  final int? status = memErrorStatusCode(error);
  return status == 401 || status == 403;
}

/// Full-bleed error state for a screen that has nothing to show (§3.6).
///
/// 64 dp `errorContainer` circle, `titleMedium` headline, `bodyMedium` detail
/// from [memErrorText], and a tonal **Try again** wired to the screen's reload.
/// Use it where a list or a detail body would have gone; a failure that still
/// has content behind it gets [errSnack] instead.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.error,
    required this.onRetry,
    this.title,
  });

  /// The raw error. It is formatted here, never before.
  final Object error;

  final VoidCallback onRetry;

  /// Headline. Defaults to "Couldn't load".
  final String? title;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MemInsets.pageH,
            vertical: MemSpace.x6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 28,
                  color: cs.onErrorContainer,
                ),
              ),
              const SizedBox(height: MemSpace.x4),
              Text(
                title ?? "Couldn't load",
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: MemSpace.x2),
              Text(
                memErrorText(error),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: MemSpace.x6),
              FilledButton.tonal(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Snackbar variant of [ErrorState] — for a failure that leaves content on
/// screen (§3.6).
///
/// Exactly one action, chosen in this order:
/// 1. **Open Settings**, deep-linked to [openSettings] (defaulting to
///    `SettingsSection.account`), whenever the error is a 401/403 — retrying a
///    rejected key is not a recovery.
/// 2. **Retry**, when [onRetry] is supplied.
/// 3. **Open Settings**, when the caller named a section for a non-auth error.
///
/// [context] is the *page's* context and is what makes the deep link possible:
/// the app-level `ScaffoldMessenger` sits **above** the root `Navigator`, so a
/// messenger alone cannot push a route. Callers that omit it get no
/// Open-Settings action rather than a dead button — screens should pass it (or
/// use `AsyncPageMixin.showError`, which threads it for you). It is re-checked
/// with `context.mounted` at press time, since a snackbar outlives its page.
void errSnack(
  ScaffoldMessengerState messenger,
  Object error, {
  VoidCallback? onRetry,
  SettingsSection? openSettings,
  BuildContext? context,
}) {
  final bool auth = memErrorIsAuth(error);
  final SettingsSection? section =
      openSettings ?? (auth ? SettingsSection.account : null);
  final bool canOpenSettings = section != null && context != null;

  SnackBarAction? action;
  if (canOpenSettings && auth) {
    action = _openSettingsAction(context, section);
  } else if (onRetry != null) {
    action = SnackBarAction(label: 'Retry', onPressed: onRetry);
  } else if (canOpenSettings) {
    action = _openSettingsAction(context, section);
  }

  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(memErrorText(error)),
      duration: action == null ? MemMotion.snack : MemMotion.snackAction,
      action: action,
    ),
  );
}

SnackBarAction _openSettingsAction(BuildContext context, SettingsSection s) {
  return SnackBarAction(
    label: 'Open Settings',
    onPressed: () {
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => SettingsPage(focusSection: s),
        ),
      );
    },
  );
}
