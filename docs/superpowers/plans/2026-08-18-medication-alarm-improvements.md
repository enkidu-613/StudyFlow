# 药物提醒交互与安卓触达改进（工作记录 2026-08-18）

> **状态：** 已完成。本文件记录本轮针对「药物计划」的功能与触达改进，供后续维护与回滚参考。

## 目标与可见结果

1. 已确认服用的剂量时间点不再响铃、不震动、不弹确认框。
2. 药物页「最近记录」显示 **已服/跳过/延后 · 药物名 · 今日第 N 次**。
3. 药物计划卡片改为 **长按卡片 → 删除按钮自右侧滑出 → 点击按钮弹确认**，确认后才删除。
4. 安卓后台/锁屏闹钟加入 **程序化循环震动**，与铃声同启停。

## 修改文件

- `apps/client/lib/features/medications/medication_alarm_service.dart`：排程时过滤已确认服用的时间点；`resync`/`upsert` 读取 dose 记录并按计划归组。
- `apps/client/lib/features/medications/medication_screen.dart`：记录「已服」后重排该计划闹钟（`medicationAlarms.upsert`）；最近记录显示药物名与当日次数；长按卡片右侧滑出删除按钮。
- `apps/client/android/app/src/main/kotlin/com/studyflow/app/StudyFlowPlatform.kt`：`AlarmSoundController` 增加 `VibrationEffect` 程序化循环震动（带 `USAGE_ALARM` 属性，Android 16 后台必需）；通知渠道关闭渠道级震动避免打断循环震动；服药渠道升级为 `studyflow_medication_alarm_v2` 规避旧渠道不可变设置。

## 关键实现说明

- **已服静音**：`_takenOccurrences()` 只归组 `outcome == taken` 的时间点；注册闹钟时命中则跳过，不触发原生 AlarmManager → 无响铃/震动/通知/弹窗。`skipped`、`delayed` 不受影响。确认服药后立即 `upsert` 重排，重启后 `resync` 同样过滤。
- **最近记录**：`_recordTile` 统计同一计划、同一自然日、不晚于当前记录的条数作为「今日第 N 次」，计划不存在时显示「未知药物」兜底。
- **长按删除**：`_SwipeablePlanCard` 用 `onLongPress` 切换展开态，`Transform.translate(-extent)` 让卡片左移露出右侧按钮；按钮 `onTap` 先弹确认再删除，确认取消则收起不收数据。
- **循环震动**：`createWaveform(0,600,400,600, repeat=0)` + `USAGE_ALARM`；渠道 `enableVibration(false)` 防一次性渠道震动打断；`VIBRATE` 权限已有。

## 验证

```bash
cd apps/client && no_proxy="127.0.0.1,localhost" flutter test
# 药物模块 12 个测试通过，全量 244 个测试通过。
cd apps/client/android && JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ./gradlew compileDebugKotlin
# BUILD SUCCESSFUL
```

新增回归测试：`test/features/medications/medication_alarm_service_test.dart`
- 已服时间点不注册闹钟、其余时间点仍注册；
- 跳过的时间点仍正常注册（只有「已服」才静音）。

## 当前已知环境

- 设备：iQOO Z9 Turbo（OriginOS 6 / Android 16），包名 `com.studyflow.studyflow`。
- Flutter 配置 JDK 为 Homebrew `openjdk@21`；本机默认 mise 的 GraalVM 21 / JDK 26 与 Android Gradle 插件不兼容，编译需用前者。
- 后台/锁屏触发依赖安卓「精确闹钟 + 通知」权限；若实测仍不震，查系统「声音与振动」总开关与勿扰豁免。

## 回滚

- 已服静音回归：还原 `medication_alarm_service.dart` 的排程过滤与 `medication_screen.dart` 的 `upsert` 调用即可。
- 循环震动回归：还原 `AlarmSoundController` 与通知渠道中震动相关改动即可。
- 注意服药渠道 ID 已升至 `v2`，回滚后已建渠道仍在设备上，不影响功能。