package com.studyflow.app

import android.app.Activity
import android.app.AlarmManager
import android.app.AlertDialog
import android.app.AppOpsManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.os.Process
import android.provider.Settings
import android.util.Log
import com.studyflow.studyflow.MainActivity
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

object StudyFlowPlatform {
    private const val channelName = "studyflow/platform"
    private const val notificationPermissionRequestCode = 7001
    private var pendingPermissionResult: MethodChannel.Result? = null

    fun register(engine: FlutterEngine, activity: Activity) {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName)
        EventChannel(engine.dartExecutor.binaryMessenger, alarmEventsChannelName)
            .setStreamHandler(AlarmEventStreamHandler)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scheduleReminder" -> scheduleReminder(activity, call.arguments, result)
                "cancelReminder" -> cancelReminder(activity, call.arguments, result)
                "playAlarm" -> playAlarm(activity, call.arguments, result)
                "getPendingAlarms" -> result.success(pendingAlarmMaps(activity))
                "acknowledgeAlarm" -> acknowledgeAlarm(activity, call.arguments, result)
                "startFocusSession" -> startFocusSession(activity, call.arguments, result)
                "cancelFocusSessionNotification" ->
                    cancelFocusSessionNotification(activity, result)
                "requestPermission" -> requestPermission(activity, call.arguments, result)
                "showUnavailablePermission" -> showUnavailablePermission(
                    activity,
                    call.arguments,
                    result,
                )
                "openPermissionSettings" -> result.success(openAppSettings(activity))
                "getUsageSummary" -> result.success(
                    unsupported("Usage summaries require separate UsageStats authorization.")
                )
                "applyRestriction", "clearRestriction" -> result.success(
                    unsupported("Device restrictions require separate authorization.")
                )
                "getPermissionStatus" -> result.success(permissionStatus(activity))
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPermission(
        activity: Activity,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Permission id is missing.", null)
        val id = map["id"] as? String
            ?: return result.error("invalid_argument", "Permission id is missing.", null)

        when (id) {
            "notifications", "userNotifications" -> requestNotificationPermission(activity, result)
            "exactAlarm" -> {
                if (canScheduleExactAlarms(activity)) {
                    result.success(permissionResult(granted = true, status = "authorized"))
                } else if (openExactAlarmSettings(activity)) {
                    result.success(permissionResult(granted = false, status = "opened_settings"))
                } else {
                    result.error("unsupported", "Exact alarm settings are unavailable.", null)
                }
            }
            "batteryOptimization" -> {
                if (isIgnoringBatteryOptimizations(activity)) {
                    result.success(permissionResult(granted = true, status = "authorized"))
                } else if (isVivoFamilyDevice()) {
                    // OriginOS replaces the stock battery-optimization flow with
                    // its own "Background power consumption management". The stock
                    // REQUEST_IGNORE_BATTERY_OPTIMIZATIONS dialog is silently
                    // ignored on vivo, so open the OEM battery app directly.
                    if (openVivoBackgroundPowerSettings(activity)) {
                        result.success(permissionResult(granted = false, status = "opened_settings"))
                    } else {
                        result.error("unsupported", "Battery optimization settings are unavailable.", null)
                    }
                } else if (openBatteryOptimizationSettings(activity)) {
                    result.success(permissionResult(granted = false, status = "opened_settings"))
                } else {
                    result.error("unsupported", "Battery optimization settings are unavailable.", null)
                }
            }
            "background" -> {
                if (!isBackgroundRestricted(activity)) {
                    result.success(permissionResult(granted = true, status = "authorized"))
                } else if (openAppSettings(activity)) {
                    result.success(permissionResult(granted = false, status = "opened_settings"))
                } else {
                    result.error("unsupported", "App settings are unavailable.", null)
                }
            }
            "usageAccess" -> {
                if (hasUsageAccess(activity)) {
                    result.success(permissionResult(granted = true, status = "authorized"))
                } else if (openSettingsIntent(activity, Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))) {
                    result.success(permissionResult(granted = false, status = "opened_settings"))
                } else {
                    result.error("unsupported", "Usage access settings are unavailable.", null)
                }
            }
            else -> result.error(
                "unsupported",
                "This permission does not have an Android authorization flow.",
                null,
            )
        }
    }

    private fun requestNotificationPermission(
        activity: Activity,
        result: MethodChannel.Result,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            hasNotificationPermission(activity)
        ) {
            return result.success(permissionResult(granted = true, status = "authorized"))
        }
        if (pendingPermissionResult != null) {
            return result.error("busy", "A permission request is already in progress.", null)
        }
        if (activity.shouldShowRequestPermissionRationale(android.Manifest.permission.POST_NOTIFICATIONS)) {
            if (openNotificationSettings(activity)) {
                return result.success(
                    permissionResult(granted = false, status = "opened_settings")
                )
            }
            return result.error("unsupported", "Notification settings are unavailable.", null)
        }
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != notificationPermissionRequestCode) {
            return false
        }
        val result = pendingPermissionResult
        pendingPermissionResult = null
        if (result == null) {
            return true
        }
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        result.success(
            permissionResult(
                granted = granted,
                status = if (granted) "authorized" else "declined",
            )
        )
        return true
    }

    private fun permissionResult(
        granted: Boolean,
        status: String,
    ): Map<String, Any> = mapOf(
        "granted" to granted,
        "status" to status,
    )

    private fun showUnavailablePermission(
        activity: Activity,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Permission dialog arguments are missing.", null)
        val title = map["title"] as? String ?: "StudyFlow"
        val message = map["message"] as? String ?: "This permission is unavailable."
        activity.runOnUiThread {
            AlertDialog.Builder(activity)
                .setTitle(title)
                .setMessage(message)
                .setPositiveButton(android.R.string.ok) { _, _ -> result.success(true) }
                .setOnCancelListener { result.success(false) }
                .show()
        }
    }

    private fun openNotificationSettings(activity: Activity): Boolean = openSettingsIntent(
        activity,
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        },
    )

    private fun openExactAlarmSettings(activity: Activity): Boolean {
        // Some OEM ROMs (vivo OriginOS, MIUI) either rename or replace the
        // stock exact-alarm permission page. If the dedicated page cannot be
        // opened, fall back to the app details page where the user can open
        // Permissions and toggle "Alarms & reminders" manually.
        val requestIntent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        return openSettingsIntent(activity, requestIntent) || openAppSettings(activity)
    }

    private fun openBatteryOptimizationSettings(activity: Activity): Boolean {
        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        return openSettingsIntent(activity, intent) || openAppSettings(activity)
    }

    private fun isVivoFamilyDevice(): Boolean {
        val brand = "${Build.MANUFACTURER} ${Build.BRAND} ${Build.DEVICE}".lowercase()
        return listOf("vivo", "iqoo", "bbk").any { brand.contains(it) }
    }

    // OriginOS "Background power consumption management" lives in the OEM
    // battery / phone-manager apps. There is no public API to toggle it, so we
    // open the OEM app the user can reach the toggle from. The component names
    // are not part of any public contract and change across versions, so try
    // the known packages in order and fall back to the stock battery page.
    private fun openVivoBackgroundPowerSettings(activity: Activity): Boolean {
        val packages = listOf(
            "com.bbk.powerpartner",
            "com.iqoo.secure",
            "com.vivo.permissionmanager",
        )
        for (packageName in packages) {
            val intent = activity.packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                if (openSettingsIntent(activity, intent)) {
                    return true
                }
            }
        }
        // Stock list of apps exempted from battery optimization. vivo maps this
        // page to its own battery settings on most recent releases.
        return openSettingsIntent(activity, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) ||
            openAppSettings(activity)
    }

    private fun openAppSettings(activity: Activity): Boolean = openSettingsIntent(
        activity,
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${activity.packageName}")
        },
    )

    private fun openSettingsIntent(activity: Activity, intent: Intent): Boolean = try {
        activity.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }

    private fun isBackgroundRestricted(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return false
        }
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as
            android.app.ActivityManager
        return activityManager.isBackgroundRestricted
    }

    private fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true
        }
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(context.packageName)
    }

    private fun hasUsageAccess(context: Context): Boolean {
        val appOpsManager = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        val mode = appOpsManager.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            context.packageName,
        )
        return mode == AppOpsManager.MODE_ALLOWED
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
        val identifier = map["id"] as? String
        val kind = map["kind"] as? String ?: "other"
        val entityId = map["entity_id"] as? String

        if (!canScheduleExactAlarms(context)) {
            return result.error(
                "permission_denied",
                "Exact alarm permission is missing.",
                null,
            )
        }

        val effectiveIdentifier = identifier
            ?: "reminder:${java.lang.System.currentTimeMillis()}"
        if (!scheduleNativeReminder(
                context,
                effectiveIdentifier,
                title,
                text,
                atMillis,
                kind,
                entityId,
            )
        ) {
            return result.error(
                "internal_error",
                "The Android alarm could not be registered.",
                null,
            )
        }
        if (identifier != null) {
            rememberReminder(context, identifier, title, text, atMillis, kind, entityId)
        }
        result.success(mapOf("kind" to "supported", "message" to "Reminder scheduled."))
    }

    private fun cancelReminder(
        context: Context,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Reminder identifier is missing.", null)
        val identifier = map["id"] as? String
            ?: return result.error("invalid_argument", "Reminder identifier is missing.", null)
        val identifiers = reminderIdsMatching(context, identifier)
        for (reminderId in identifiers) {
            cancelNativeReminder(context, reminderId)
            forgetReminder(context, reminderId)
            forgetPendingAlarm(context, reminderId)
            cancelAlarmNotification(context, reminderId)
        }
        AlarmRingingService.restartForPending(context)
        result.success(mapOf("kind" to "supported", "message" to "Reminder cancelled."))
    }

    private fun playAlarm(
        context: Context,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Alarm arguments are missing.", null)
        val title = map["title"] as? String ?: "StudyFlow alarm"
        val text = map["text"] as? String ?: "A focus session has ended."
        val identifier = map["id"] as? String
        val kind = map["kind"] as? String ?: "other"
        val entityId = map["entity_id"] as? String
        val alarmId = identifier ?: "alarm:${requestCodeFor(title + text)}"
        rememberPendingAlarm(context, alarmId, title, text, kind, entityId)
        AlarmEventDispatcher.emit(
            mapOf(
                "id" to alarmId,
                "title" to title,
                "text" to text,
                "kind" to kind,
                "entity_id" to entityId,
            )
        )
        if (hasNotificationPermission(context)) {
            postAlarmNotification(
                context,
                title,
                text,
                requestCodeFor(alarmId),
                ongoing = true,
                kind = kind,
            )
        }
        if (hasNotificationPermission(context)) {
            AlarmRingingService.start(
                context,
                alarmId,
                shouldVibrate = kind == "medication",
            )
        } else {
            AlarmSoundController.play(
                context,
                shouldVibrate = kind == "medication",
            )
        }
        result.success(
            mapOf(
                "kind" to "supported",
                "message" to if (hasNotificationPermission(context)) {
                    "Alarm played."
                } else {
                    "Alarm sound played; notification permission is missing."
                },
            )
        )
    }

    private fun acknowledgeAlarm(
        context: Context,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Alarm identifier is missing.", null)
        val identifier = map["id"] as? String
            ?: return result.error("invalid_argument", "Alarm identifier is missing.", null)
        forgetPendingAlarm(context, identifier)
        cancelAlarmNotification(context, identifier)
        // The start-of-focus informational notification uses a separate
        // stable id. Acknowledging the end alarm is the user's explicit
        // confirmation that both notifications can be removed.
        cancelFocusSessionNotification(context)
        AlarmRingingService.restartForPending(context)
        result.success(mapOf("kind" to "supported", "message" to "Alarm acknowledged."))
    }

    private fun startFocusSession(
        context: Context,
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val map = arguments as? Map<*, *>
            ?: return result.error("invalid_argument", "Focus arguments are missing.", null)
        val title = map["title"] as? String ?: "StudyFlow focus"
        if (hasNotificationPermission(context)) {
            postNotification(context, title, "Focus session started.", 2000)
        }
        result.success(
            mapOf(
                "kind" to "supported",
                "message" to if (hasNotificationPermission(context)) {
                    "Focus notification posted."
                } else {
                    "Focus started; notification permission is missing."
                },
            )
        )
    }

    private fun cancelFocusSessionNotification(
        context: Context,
        result: MethodChannel.Result,
    ) {
        cancelFocusSessionNotification(context)
        result.success(
            mapOf("kind" to "supported", "message" to "Focus notification cancelled.")
        )
    }

    private fun cancelFocusSessionNotification(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(focusSessionNotificationId)
    }

    private fun permissionStatus(context: Context): List<Map<String, Any>> {
        val notificationsGranted = hasNotificationPermission(context)
        val exactAlarmGranted = canScheduleExactAlarms(context)
        val backgroundRestricted = isBackgroundRestricted(context)
        val batteryOptimizationAllowed = isIgnoringBatteryOptimizations(context)

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
                if (exactAlarmGranted) {
                    "granted"
                } else {
                    "not granted; open Permissions → Alarms & reminders and enable it"
                },
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
                if (batteryOptimizationAllowed) {
                    if (isVivoFamilyDevice()) {
                        "vivo 后台耗电管理状态无法自动检测；请确认「设置 → 电池 → 后台耗电管理」已将 StudyFlow 设为允许"
                    } else {
                        "allowed"
                    }
                } else {
                    "restricted; open Battery → Background power consumption management and allow StudyFlow"
                },
            ),
            permission(
                "usageAccess",
                true,
                hasUsageAccess(context),
                if (hasUsageAccess(context)) "granted" else "not granted",
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
        val reminderId = intent.getStringExtra("reminder_id")
        val kind = intent.getStringExtra("kind") ?: "other"
        Log.i(
            alarmLogTag,
            "ReminderReceiver fired id=$reminderId kind=$kind " +
                "at=${System.currentTimeMillis()}",
        )
        if (reminderId != null) {
            val entityId = intent.getStringExtra("entity_id")
            rememberPendingAlarm(context, reminderId, title, text, kind, entityId)
            // The one-shot AlarmManager entry has fired. Keep the pending
            // acknowledgement record, but remove the stale scheduled entry
            // so boot/resync cannot recreate an already-fired alarm.
            forgetReminder(context, reminderId)
            AlarmEventDispatcher.emit(
                mapOf(
                    "id" to reminderId,
                    "title" to title,
                    "text" to text,
                    "kind" to kind,
                    "entity_id" to entityId,
                )
            )
        }
        if (hasNotificationPermission(context)) {
            postAlarmNotification(
                context,
                title,
                text,
                notificationId,
                ongoing = true,
                kind = kind,
            )
        }
        if (reminderId != null) {
            try {
                AlarmRingingService.start(
                    context,
                    reminderId,
                    shouldVibrate = kind == "medication",
                )
            } catch (error: Throwable) {
                Log.e(alarmLogTag, "Unable to start alarm foreground service", error)
            }
        } else {
            AlarmSoundController.play(
                context,
                shouldVibrate = kind == "medication",
            )
        }
    }
}

class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null) {
            return
        }
        val pendingResult = goAsync()
        Thread {
            rescheduleStoredReminders(context)
            pendingResult.finish()
        }.start()
    }
}

private object AlarmEventDispatcher {
    private var sink: EventChannel.EventSink? = null

    fun attach(eventSink: EventChannel.EventSink?) {
        sink = eventSink
    }

    fun emit(alarm: Map<String, Any?>) {
        sink?.success(alarm)
    }
}

private object AlarmEventStreamHandler : EventChannel.StreamHandler {
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        AlarmEventDispatcher.attach(events)
    }

    override fun onCancel(arguments: Any?) {
        AlarmEventDispatcher.attach(null)
    }
}

class AlarmRingingService : android.app.Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "StudyFlow:AlarmRinging",
        ).apply {
            acquire()
        }
        Log.i(alarmLogTag, "AlarmRingingService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val alarmId = intent?.getStringExtra("alarm_id")
        if (alarmId == null) {
            Log.w(alarmLogTag, "AlarmRingingService started without an alarm id")
            stopSelfResult(startId)
            return START_NOT_STICKY
        }
        val alarm = pendingAlarm(this, alarmId)
        if (alarm == null) {
            Log.w(alarmLogTag, "AlarmRingingService has no pending alarm for id=$alarmId")
            stopIfIdle(this)
            return START_NOT_STICKY
        }
        val shouldVibrate = intent.getBooleanExtra(
            "should_vibrate",
            alarm.optString("kind", "other") == "medication",
        )
        val notificationId = requestCodeFor(alarmId)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForeground(
                notificationId,
                buildAlarmNotification(
                    this,
                    alarm.optString("title", "StudyFlow 提醒"),
                    alarm.optString("text", ""),
                    notificationId,
                    ongoing = true,
                    kind = alarm.optString("kind", "other"),
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startForeground(
                notificationId,
                buildAlarmNotification(
                    this,
                    alarm.optString("title", "StudyFlow 提醒"),
                    alarm.optString("text", ""),
                    notificationId,
                    ongoing = true,
                    kind = alarm.optString("kind", "other"),
                ),
            )
        }
        Log.i(alarmLogTag, "AlarmRingingService starting looping sound id=$alarmId")
        AlarmSoundController.play(
            this,
            shouldVibrate = shouldVibrate,
        )
        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(alarmLogTag, "AlarmRingingService destroyed")
        AlarmSoundController.stop()
        wakeLock?.let { lock ->
            if (lock.isHeld) {
                lock.release()
            }
        }
        wakeLock = null
        @Suppress("DEPRECATION")
        stopForeground(true)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): android.os.IBinder? = null

    companion object {
        fun start(
            context: Context,
            alarmId: String,
            shouldVibrate: Boolean = false,
        ) {
            val intent = Intent(context, AlarmRingingService::class.java)
                .putExtra("alarm_id", alarmId)
                .putExtra("should_vibrate", shouldVibrate)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    context.startService(intent)
                }
            } catch (error: Throwable) {
                // An exact alarm is allowed to start a foreground service on
                // modern Android. Some OEM builds still reject the first
                // start attempt while waking from a frozen process, so retry
                // as a normal service before the receiver gives up.
                Log.e(alarmLogTag, "Foreground service start rejected for id=$alarmId", error)
                @Suppress("DEPRECATION")
                context.startService(intent)
            }
        }

        fun stopIfIdle(context: Context) {
            if (pendingAlarmMaps(context).isEmpty()) {
                context.stopService(Intent(context, AlarmRingingService::class.java))
            }
        }

        fun restartForPending(context: Context) {
            AlarmSoundController.stop()
            val next = pendingAlarmMaps(context).firstOrNull()
            val nextId = next?.get("id") as? String
            if (nextId != null) {
                // Reuse the running service when another alarm is pending.
                // Stopping and immediately starting it races with onDestroy,
                // whose cleanup would otherwise stop the new ringtone too.
                start(
                    context,
                    nextId,
                    shouldVibrate = next.get("kind") == "medication",
                )
            } else {
                context.stopService(Intent(context, AlarmRingingService::class.java))
            }
        }
    }
}

private const val reminderPreferencesName = "studyflow_reminders"
private const val storedRemindersKey = "scheduled"
private const val pendingAlarmsKey = "pending"
private const val reminderChannelId = "studyflow_reminders"
private const val focusSessionNotificationId = 2000
// The foreground service owns the looping alarm sound. Keep the notification
// channel silent so Android does not add a second, overlapping alert sound.
// The version suffix also avoids reusing the old channel whose sound setting
// is immutable after it has been created on the device.
private const val alarmChannelId = "studyflow_alarm_v3_silent"
// v2: bumped so devices that already created v1 (with channel vibration
// enabled) drop the stale one-shot channel vibration, which would otherwise
// cancel the repeating programmatic alarm vibration.
private const val medicationAlarmChannelId = "studyflow_medication_alarm_v2"
private const val alarmEventsChannelName = "studyflow/alarm_events"
private const val alarmLogTag = "StudyFlowAlarm"

private fun requestCodeFor(identifier: String?): Int {
    if (identifier == null) {
        return (java.lang.System.currentTimeMillis() % Int.MAX_VALUE).toInt()
    }
    var hash = 0
    for (char in identifier) {
        hash = hash * 31 + char.code
    }
    return hash and Int.MAX_VALUE
}

private fun pendingIntentFor(
    context: Context,
    reminderId: String,
    title: String = "StudyFlow reminder",
    text: String = "Scheduled block",
    kind: String = "other",
    entityId: String? = null,
    flags: Int = PendingIntent.FLAG_UPDATE_CURRENT,
): PendingIntent? {
    val requestCode = requestCodeFor(reminderId)
    val intent = Intent(context, ReminderReceiver::class.java)
        .putExtra("reminder_id", reminderId)
        .putExtra("title", title)
        .putExtra("text", text)
        .putExtra("kind", kind)
        .putExtra("entity_id", entityId)
        .putExtra("notification_id", requestCode)
    val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        PendingIntent.FLAG_IMMUTABLE
    } else {
        0
    }
    return PendingIntent.getBroadcast(
        context,
        requestCode,
        intent,
        flags or immutableFlag,
    )
}

private fun scheduleNativeReminder(
    context: Context,
    reminderId: String,
    title: String,
    text: String,
    atMillis: Long,
    kind: String = "other",
    entityId: String? = null,
): Boolean {
    if (!canScheduleExactAlarms(context)) {
        return false
    }
    val pendingIntent = pendingIntentFor(
        context,
        reminderId,
        title,
        text,
        kind,
        entityId,
    )
        ?: return false
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            // This is the Android alarm type intended for user-visible clocks,
            // calendars and reminders. Unlike a regular exact alarm, Android
            // treats it as a critical alarm while the device is idle and
            // provides the temporary execution window needed to start the
            // foreground ringing service.
            val showIntent = alarmClockShowIntentFor(context, reminderId)
                ?: return false
            alarmManager.setAlarmClock(
                AlarmManager.AlarmClockInfo(atMillis, showIntent),
                pendingIntent,
            )
        } else {
            @Suppress("DEPRECATION")
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, atMillis, pendingIntent)
        }
        Log.i(alarmLogTag, "Scheduled alarm id=$reminderId at=$atMillis")
    } catch (error: SecurityException) {
        Log.e(alarmLogTag, "Unable to schedule alarm id=$reminderId", error)
        return false
    }
    return true
}

private fun cancelNativeReminder(context: Context, reminderId: String) {
    val pendingIntent = pendingIntentFor(
        context,
        reminderId,
        flags = PendingIntent.FLAG_NO_CREATE,
    ) ?: return
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
    alarmManager.cancel(pendingIntent)
    pendingIntent.cancel()
    alarmClockShowIntentFor(
        context,
        reminderId,
        flags = PendingIntent.FLAG_NO_CREATE,
    )?.cancel()
    Log.i(alarmLogTag, "Cancelled alarm id=$reminderId")
}

private fun alarmClockShowIntentFor(
    context: Context,
    reminderId: String,
    flags: Int = PendingIntent.FLAG_UPDATE_CURRENT,
): PendingIntent? {
    val intent = Intent(context, MainActivity::class.java).apply {
        action = "studyflow.pending_alarm"
        this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        putExtra("reminder_id", reminderId)
    }
    val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        PendingIntent.FLAG_IMMUTABLE
    } else {
        0
    }
    return PendingIntent.getActivity(
        context,
        requestCodeFor("show:$reminderId"),
        intent,
        flags or immutableFlag,
    )
}

private fun remindersPreferences(context: Context) =
    context.getSharedPreferences(reminderPreferencesName, Context.MODE_PRIVATE)

private fun storedReminders(context: Context): JSONObject = try {
    JSONObject(remindersPreferences(context).getString(storedRemindersKey, "{}") ?: "{}")
} catch (_: Exception) {
    JSONObject()
}

private fun storedPendingAlarms(context: Context): JSONObject = try {
    JSONObject(remindersPreferences(context).getString(pendingAlarmsKey, "{}") ?: "{}")
} catch (_: Exception) {
    JSONObject()
}

private fun rememberReminder(
    context: Context,
    reminderId: String,
    title: String,
    text: String,
    atMillis: Long,
    kind: String = "other",
    entityId: String? = null,
) {
    val reminders = storedReminders(context)
    reminders.put(
        reminderId,
        JSONObject()
            .put("title", title)
            .put("text", text)
            .put("at", atMillis)
            .put("kind", kind)
            .put("entity_id", entityId),
    )
    remindersPreferences(context)
        .edit()
        .putString(storedRemindersKey, reminders.toString())
        .apply()
}

private fun rememberPendingAlarm(
    context: Context,
    alarmId: String,
    title: String,
    text: String,
    kind: String,
    entityId: String?,
) {
    val alarms = storedPendingAlarms(context)
    alarms.put(
        alarmId,
        JSONObject()
            .put("id", alarmId)
            .put("title", title)
            .put("text", text)
            .put("kind", kind)
            .put("entity_id", entityId),
    )
    remindersPreferences(context)
        .edit()
        .putString(pendingAlarmsKey, alarms.toString())
        .apply()
}

private fun forgetReminder(context: Context, reminderId: String) {
    val reminders = storedReminders(context)
    reminders.remove(reminderId)
    remindersPreferences(context)
        .edit()
        .putString(storedRemindersKey, reminders.toString())
        .apply()
}

private fun forgetPendingAlarm(context: Context, alarmId: String) {
    val alarms = storedPendingAlarms(context)
    alarms.remove(alarmId)
    remindersPreferences(context)
        .edit()
        .putString(pendingAlarmsKey, alarms.toString())
        .apply()
}

private fun pendingAlarmMaps(context: Context): List<Map<String, Any?>> {
    val alarms = storedPendingAlarms(context)
    val keys = alarms.keys()
    val result = mutableListOf<Map<String, Any?>>()
    while (keys.hasNext()) {
        val key = keys.next()
        val alarm = alarms.optJSONObject(key) ?: continue
        result += mapOf(
            "id" to key,
            "title" to alarm.optString("title", "StudyFlow 提醒"),
            "text" to alarm.optString("text", ""),
            "kind" to alarm.optString("kind", "other"),
            "entity_id" to alarm.optString("entity_id").takeIf { it.isNotEmpty() },
        )
    }
    return result
}

private fun pendingAlarm(context: Context, alarmId: String): JSONObject? =
    storedPendingAlarms(context).optJSONObject(alarmId)

private fun cancelAlarmNotification(context: Context, alarmId: String) {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.cancel(requestCodeFor(alarmId))
}

private fun reminderIdsMatching(context: Context, identifier: String): List<String> {
    val ids = mutableListOf(identifier)
    val reminders = storedReminders(context)
    val keys = reminders.keys()
    while (keys.hasNext()) {
        val key = keys.next()
        if (
            key == identifier ||
            key.startsWith("$identifier#") ||
            key.startsWith("$identifier:")
        ) {
            if (!ids.contains(key)) {
                ids += key
            }
        }
    }
    return ids
}

private fun rescheduleStoredReminders(context: Context) {
    // Notification permission controls visibility in the notification drawer,
    // not whether AlarmManager can wake the device and start the alarm service.
    // Keep rescheduling exact alarms even when the user has not granted drawer
    // notifications yet; the ringtone must still work in the background.
    if (!canScheduleExactAlarms(context)) {
        return
    }
    val reminders = storedReminders(context)
    val keys = reminders.keys()
    val now = System.currentTimeMillis()
    val expired = mutableListOf<String>()
    while (keys.hasNext()) {
        val reminderId = keys.next()
        val data = reminders.optJSONObject(reminderId) ?: continue
        val atMillis = data.optLong("at", 0L)
        if (atMillis <= now) {
            expired += reminderId
            continue
        }
        scheduleNativeReminder(
            context,
            reminderId,
            data.optString("title", "StudyFlow reminder"),
            data.optString("text", "Scheduled block"),
            atMillis,
            data.optString("kind", "other"),
            data.optString("entity_id").takeIf { it.isNotEmpty() },
        )
    }
    if (expired.isNotEmpty()) {
        for (reminderId in expired) {
            reminders.remove(reminderId)
        }
        remindersPreferences(context)
            .edit()
            .putString(storedRemindersKey, reminders.toString())
            .apply()
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
                reminderChannelId,
                "StudyFlow reminders",
                NotificationManager.IMPORTANCE_HIGH,
            )
        )
        val notification = android.app.Notification.Builder(context, reminderChannelId)
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

private fun postAlarmNotification(
    context: Context,
    title: String,
    text: String,
    notificationId: Int,
    ongoing: Boolean = true,
    kind: String = "other",
) {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    manager.notify(
        notificationId,
        buildAlarmNotification(context, title, text, notificationId, ongoing, kind),
    )
}

private fun buildAlarmNotification(
    context: Context,
    title: String,
    text: String,
    notificationId: Int,
    ongoing: Boolean,
    kind: String = "other",
): Notification {
    val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    val openIntent = Intent(context, MainActivity::class.java).apply {
        action = "studyflow.pending_alarm"
        flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    val immutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        PendingIntent.FLAG_IMMUTABLE
    } else {
        0
    }
    val contentIntent = PendingIntent.getActivity(
        context,
        requestCodeFor("open:$notificationId"),
        openIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag,
    )
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val isMedication = kind == "medication"
        val channelId = if (isMedication) medicationAlarmChannelId else alarmChannelId
        val channel = NotificationChannel(
            channelId,
            if (isMedication) "StudyFlow medication reminders" else "StudyFlow alarms",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            setSound(null, null)
            // Vibration is driven programmatically by AlarmSoundController;
            // a channel-level one-shot vibration would cancel the repeating
            // alarm vibration started by the foreground service.
            enableVibration(false)
            enableLights(true)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
        val notification = Notification.Builder(context, channelId)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setCategory(Notification.CATEGORY_ALARM)
            .setPriority(Notification.PRIORITY_MAX)
            .setContentIntent(contentIntent)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .setOnlyAlertOnce(true)
            .build()
        return notification
    } else {
        @Suppress("DEPRECATION")
        val notification = Notification.Builder(context)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(text)
            .setDefaults(Notification.DEFAULT_LIGHTS)
            .setContentIntent(contentIntent)
            .setOngoing(ongoing)
            .setAutoCancel(!ongoing)
            .build()
        return notification
    }
}

private object AlarmSoundController {
    private var activeRingtone: Ringtone? = null
    private var activeVibrator: Vibrator? = null

    fun play(context: Context, shouldVibrate: Boolean = false) {
        stop()
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            ?: return
        val ringtone = RingtoneManager.getRingtone(context.applicationContext, uri) ?: return
        ringtone.audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ringtone.isLooping = true
        }
        activeRingtone = ringtone
        ringtone.play()
        if (shouldVibrate) {
            startVibration(context)
        }
    }

    fun stop() {
        activeRingtone?.stop()
        activeRingtone = null
        activeVibrator?.cancel()
        activeVibrator = null
    }

    // Medication vibration runs programmatically instead of via the
    // notification channel: channel settings are immutable after creation,
    // and a repeating waveform with USAGE_ALARM attributes is required for
    // background vibration on Android 16. Schedule and focus alarms call
    // play() with shouldVibrate=false, so they remain audible only.
    private fun startVibration(context: Context) {
        try {
            val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager =
                    context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
                manager.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }
            if (!vibrator.hasVibrator()) {
                return
            }
            val attributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val pattern = longArrayOf(0L, 600L, 400L, 600L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createWaveform(pattern, 0), attributes)
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(pattern, 0, attributes)
            }
            activeVibrator = vibrator
        } catch (error: Throwable) {
            Log.e(alarmLogTag, "Unable to start alarm vibration", error)
        }
    }
}
