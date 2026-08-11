import 'dart:collection';

import 'schedule_block.dart';

final class ScheduleViolation {
  ScheduleViolation({required this.code, required Iterable<String> blockIds})
      : blockIds = UnmodifiableListView<String>(List<String>.from(blockIds));

  final String code;
  final List<String> blockIds;
}

abstract final class ScheduleRules {
  static List<ScheduleViolation> validateNoOverlap(
    Iterable<ScheduleBlock> blocks,
  ) {
    final orderedBlocks = blocks.toList(growable: false)..sort(_compareBlocks);
    final violations = <ScheduleViolation>[];

    for (var leftIndex = 0; leftIndex < orderedBlocks.length; leftIndex++) {
      final left = orderedBlocks[leftIndex];
      for (var rightIndex = leftIndex + 1;
          rightIndex < orderedBlocks.length;
          rightIndex++) {
        final right = orderedBlocks[rightIndex];
        if (!right.start.isBefore(left.end)) {
          break;
        }
        violations.add(
          ScheduleViolation(
            code: left.isLocked || right.isLocked
                ? 'locked_block_overlap'
                : 'schedule_block_overlap',
            blockIds: <String>[left.id, right.id],
          ),
        );
      }
    }
    return List<ScheduleViolation>.unmodifiable(violations);
  }

  static int _compareBlocks(ScheduleBlock left, ScheduleBlock right) {
    final startComparison = left.start.compareTo(right.start);
    if (startComparison != 0) {
      return startComparison;
    }
    final endComparison = left.end.compareTo(right.end);
    if (endComparison != 0) {
      return endComparison;
    }
    return left.id.compareTo(right.id);
  }
}
