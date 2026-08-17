import 'package:studyflow_domain/domain.dart';

final class ScheduleHistoryEntry {
  const ScheduleHistoryEntry({
    required this.block,
    required this.occurrenceStart,
    required this.occurrenceEnd,
    required this.feedback,
  });

  final ScheduleBlock block;
  final DateTime occurrenceStart;
  final DateTime occurrenceEnd;
  final ScheduleFeedback? feedback;
}

List<ScheduleBlock> currentBlocks(List<ScheduleBlock> blocks, DateTime now) {
  final current = now.toUtc();
  return blocks.where((block) {
    if (block.repeatRule == ScheduleRepeatRule.none) {
      return block.end.isAfter(current);
    }
    return block.occurrencesAfter(current, limit: 1).isNotEmpty;
  }).toList(growable: false);
}

List<ScheduleHistoryEntry> historyEntries({
  required List<ScheduleBlock> blocks,
  required List<ScheduleFeedback> feedback,
  required DateTime from,
  required DateTime until,
}) {
  final feedbackByOccurrence = <String, ScheduleFeedback>{
    for (final item in feedback)
      _feedbackKey(item.scheduleBlockId, item.occurrenceEnd): item,
  };
  final entries = <ScheduleHistoryEntry>[];
  for (final block in blocks) {
    final duration = block.end.difference(block.start);
    for (final occurrenceStart in block.occurrencesOverlapping(from, until)) {
      final occurrenceEnd = occurrenceStart.add(duration);
      if (!occurrenceEnd.isAfter(from.toUtc()) ||
          !occurrenceEnd.isBefore(until.toUtc())) {
        continue;
      }
      entries.add(ScheduleHistoryEntry(
        block: block,
        occurrenceStart: occurrenceStart,
        occurrenceEnd: occurrenceEnd,
        feedback: feedbackByOccurrence[_feedbackKey(block.id, occurrenceEnd)],
      ));
    }
  }
  entries
      .sort((left, right) => right.occurrenceEnd.compareTo(left.occurrenceEnd));
  return entries;
}

String _feedbackKey(String blockId, DateTime occurrenceEnd) =>
    '$blockId@${occurrenceEnd.toUtc().microsecondsSinceEpoch}';
