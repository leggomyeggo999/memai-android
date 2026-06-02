import 'package:flutter/foundation.dart';

/// One-shot dispatch from shell (e.g. home screen widget tap) → chat executes text.
class QueuedPromptJob {
  const QueuedPromptJob({
    required this.text,
    required this.notificationTitle,
    required this.notifyOnComplete,
  });

  final String text;
  /// Short label used in notifications (widget runs).
  final String notificationTitle;
  final bool notifyOnComplete;
}

/// FIFO queue for prompt jobs; supports multiple pending runs.
class ChatPromptQueue extends ChangeNotifier {
  final List<QueuedPromptJob> _pending = [];

  bool get hasPending => _pending.isNotEmpty;

  void enqueue(QueuedPromptJob job) {
    _pending.add(job);
    notifyListeners();
  }

  /// Removes and returns all pending jobs (consumer drains in order).
  List<QueuedPromptJob> drainAll() {
    if (_pending.isEmpty) return const [];
    final copy = List<QueuedPromptJob>.from(_pending);
    _pending.clear();
    return copy;
  }
}
