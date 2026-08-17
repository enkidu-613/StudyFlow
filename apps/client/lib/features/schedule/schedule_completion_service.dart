import 'dart:async';

import 'package:studyflow_domain/domain.dart';

final class ScheduleCompletionEvent {
  const ScheduleCompletionEvent({
    required this.block,
    required this.occurrenceStart,
    required this.occurrenceEnd,
  });

  final ScheduleBlock block;
  final DateTime occurrenceStart;
  final DateTime occurrenceEnd;
}

/// Emits concrete schedule instances when their planned end is reached.
final class ScheduleCompletionService {
  final StreamController<ScheduleCompletionEvent> _events =
      StreamController<ScheduleCompletionEvent>.broadcast();

  Stream<ScheduleCompletionEvent> get events => _events.stream;

  void notifyEnded({
    required ScheduleBlock block,
    required DateTime occurrenceStart,
  }) {
    _events.add(ScheduleCompletionEvent(
      block: block,
      occurrenceStart: occurrenceStart.toUtc(),
      occurrenceEnd:
          occurrenceStart.toUtc().add(block.end.difference(block.start)),
    ));
  }

  Future<void> dispose() => _events.close();
}
