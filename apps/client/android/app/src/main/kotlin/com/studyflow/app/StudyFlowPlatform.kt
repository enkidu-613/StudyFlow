package com.studyflow.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object StudyFlowPlatform {
    private const val channelName = "studyflow/platform"
    private const val channelId = "studyflow_reminders"

    fun register(engine: FlutterEngine, context: Context) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleReminder" -> scheduleReminder(context, call.arguments, result)
                "startFocusSession" -> startFocusSession(context, call.arguments, result)
                "getUsageSummary" -> result.success(
                    unsupported("Usage summaries require separate UsageStats authorization.")
                )
                "applyRestriction", "clearRestriction" -> result.success(
                    unsupported("Device restrictions require separate authorization.")
                )
                "getPermissionStatus" -> result.success(permissionStatus(context))
                else -> result.notImplemented()
            }
        }
    }

    private fun scheduleReminder(
        context: Context,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Reminder arguments are missing.", null)
        val title = map["title"] as? String ?: "StudyFlow reminder"
        val text = map["text"] as? String ?: "Scheduled block"
        val atMillis = (map["at"] as? Number)?.toLong()
            ?: return result.error("invalid_argument", "Reminder time is missing.", null)

        if (!hasNotificationPermission(context)) {
            return result.error(
                "permission_denied",
                "Notification permission is missing.",
                null,
            )
        }
        if (!canScheduleExactAlarms(context)) {
            return result.error(
                "permission_denied",
                "Exact alarm permission is missing.",
                null,
            )
        }

        val requestCode = (java.lang.System.currentTimeMillis() % Int.MAX_VALUE).toInt()
        val notificationId = requestCode
        val intent = Intent(context, ReminderReceiver::class.java)
            .putExtra("title", title)
            .putExtra("text", text)
            .putExtra("notification_id", notificationId)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                atMillis,
                pendingIntent,
            )
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, atMillis, pendingIntent)
        }
        result.success(mapOf("kind" to "supported", "message" to "Reminder scheduled."))
    }

    private fun startFocusSession(
        context: Context,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Focus arguments are missing.", null)
        if (!hasNotificationPermission(context)) {
            return result.error(
                "permission_denied",
                "Notification permission is missing.",
                null,
            )
        }
        val title = map["title"] as? String ?: "StudyFlow focus"
        postNotification(context, title, "Focus session started.", 2000)
        result.success(
            mapOf("kind" to "supported", "message" to "Focus notification posted.")
        )
    }

    private fun permissionStatus(context: Context): List<Map<String, Any>> {
        val notificationsGranted = hasNotificationPermission(context)
        val exactAlarmGranted = canScheduleExactAlarms(context)
        val backgroundRestricted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as
                android.app.ActivityManager
            activityManager.isBackgroundRestricted
        } else {
            false
        }
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val batteryOptimizationAllowed = powerManager.isIgnoringBatteryOptimizations(
            context.packageName
        )

        return listOf(
            permission(
                "notifications",
                true,
                notificationsGranted,
                if (notificationsGranted) "granted" else "not granted",
            ),
            permission(
                "exactAlarm",
                true,
                exactAlarmGranted,
                if (exactAlarmGranted) "granted" else "not granted",
            ),
            permission(
                "background",
                true,
                !backgroundRestricted,
                if (backgroundRestricted) "background restricted" else "not restricted",
            ),
            permission(
                "batteryOptimization",
                true,
                batteryOptimizationAllowed,
                if (batteryOptimizationAllowed) "allowed" else "restricted",
            ),
            permission(
                "usageAccess",
                false,
                false,
                "requires separate authorization",
            ),
            permission(
                "userNotifications",
                true,
                notificationsGranted,
                if (notificationsGranted) "granted" else "not granted",
            ),
            permission("menuBar", false, false, "not applicable on Android"),
            permission("focus", true, true, "in-app focus workflow"),
        )
    }

    private fun permission(
        id: String,
        available: Boolean,
        allowed: Boolean,
        detail: String,
    ): Map<String, Any> = mapOf(
        "id" to id,
        "available" to available,
        "allowed" to allowed,
        "detail" to detail,
    )

    private fun unsupported(message: String): Map<String, String> = mapOf(
        "kind" to "unsupported",
        "message" to message,
    )
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) {
            return
        }
        val title = intent.getStringExtra("title") ?: "StudyFlow reminder"
        val text = intent.getStringExtra("text") ?: "Scheduled block"
        val notificationId = intent.getIntExtra("notification_id", 1000)
        postNotification(context, title, text, notificationId)
    }
}

private fun hasNotificationPermission(context: Context): Boolean =
    Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
        context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED

private fun canScheduleExactAlarms(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
        return true
    }
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    return alarmManager.canScheduleExactAlarms()
}

private fun postNotification(
    context: Context,
    title: String,
    text: String,
    notificationId: Int,
) {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        manager.createNotificationChannel(
            NotificationChannel(
                "studyflow_reminders",
                "StudyFlow reminders",
                NotificationManager.IMPORTANCE_HIGH,
            )
        )
        val notification = android.app.Notification.Builder(context, "studyflow_reminders")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        manager.notify(notificationId, notification)
    } else {
        @Suppress("DEPRECATION")
        val notification = android.app.Notification.Builder(context)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        manager.notify(notificationId, notification)
    }
}
