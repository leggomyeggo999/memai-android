import 'package:intl/intl.dart';

/// Human date labels (§3.15) — **presentation only**.
///
/// These never become a key, a sort order, or an identity. The Notes timeline
/// still groups by `DateFormat.yMMMEd().format(updatedAt.toLocal())`; the label
/// is what the group *header* renders, and nothing else reads it.
///
/// Sentence case throughout: `Today`, `Yesterday`, `Monday`, `Mar 4`. ALL-CAPS
/// date headers are the named problem in `#15`.

/// Whole-day label for a group header: `Today` / `Yesterday` / the weekday name
/// (within the last week) / `Mar 4` (older) / `Mar 4, 2024` (another year).
///
/// [now] exists for tests; production callers omit it.
String memDayLabel(DateTime when, {DateTime? now}) {
  final DateTime local = when.toLocal();
  final DateTime today = (now ?? DateTime.now()).toLocal();
  final int days = _wholeDaysBetween(local, today);

  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return DateFormat.EEEE().format(local);
  return _absoluteDate(local, today);
}

/// Compact relative time for a row's trailing metadata: `now`, `5m`, `2h`,
/// `Mon`, `Mar 4`, `Mar 4, 2024`.
///
/// Tabular figures come from the `TextTheme` (§2.4), so these never shift
/// layout as they tick.
String memRelativeTime(DateTime when, {DateTime? now}) {
  final DateTime local = when.toLocal();
  final DateTime today = (now ?? DateTime.now()).toLocal();
  final Duration elapsed = today.difference(local);

  // A clock-skewed or future timestamp reads as `now` for the first minute and
  // then falls through to an absolute date — never a negative counter.
  if (elapsed.isNegative) {
    return elapsed.inSeconds > -60 ? 'now' : _absoluteDate(local, today);
  }
  if (elapsed.inSeconds < 60) return 'now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h';

  final int days = _wholeDaysBetween(local, today);
  if (days > 0 && days < 7) return DateFormat.E().format(local);
  return _absoluteDate(local, today);
}

/// `Mar 4`, or `Mar 4, 2024` once the year stops being obvious.
String _absoluteDate(DateTime local, DateTime today) {
  if (local.year == today.year) return DateFormat.MMMd().format(local);
  return DateFormat.yMMMd().format(local);
}

/// Calendar days between two local timestamps, counted from midnight to
/// midnight so a 23- or 25-hour DST day still counts as exactly one day.
int _wholeDaysBetween(DateTime a, DateTime b) {
  final DateTime from = DateTime(a.year, a.month, a.day);
  final DateTime to = DateTime(b.year, b.month, b.day);
  return (to.difference(from).inHours / 24).round();
}
