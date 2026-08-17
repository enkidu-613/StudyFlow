import 'package:flutter/material.dart';
import 'package:studyflow/features/alarm/pending_alarm.dart';
import 'package:studyflow_platform_contract/platform_contract.dart';

Future<bool?> showPendingAlarmDialog(
  BuildContext context,
  PendingAlarm alarm, {
  required Future<CapabilityResult> Function() acknowledge,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      var busy = false;
      String? error;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> confirm() async {
            if (busy) return;
            setState(() {
              busy = true;
              error = null;
            });
            final result = await acknowledge();
            if (!context.mounted) return;
            if (result.isSupported) {
              Navigator.of(dialogContext).pop(true);
              return;
            }
            setState(() {
              busy = false;
              error = result.message;
            });
          }

          final isFocus = alarm.kind == PendingAlarmKind.focus;
          return AlertDialog(
            title: Row(
              children: <Widget>[
                Icon(isFocus ? Icons.timer : Icons.notifications_active),
                const SizedBox(width: 12),
                Expanded(child: Text(alarm.title)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(alarm.text),
                const SizedBox(height: 12),
                Text(
                  isFocus ? '专注时间已结束，请确认。' : '日程提醒已到，请确认。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (error != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    '关闭提醒失败：$error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: <Widget>[
              FilledButton.icon(
                onPressed: busy ? null : confirm,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(busy ? '正在关闭…' : '确认并关闭提醒'),
              ),
            ],
          );
        },
      );
    },
  );
}
