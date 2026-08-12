import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:studyflow/l10n/app_localizations.dart';

/// Wraps [child] in a MaterialApp with StudyFlow localization delegates so
/// widget tests can render localized text deterministically.
Widget l10nApp(Widget child, {Locale locale = const Locale('zh')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const <Locale>[
      Locale('zh'),
      Locale('en'),
    ],
    home: child,
  );
}

/// Pumps [child] with localization delegates and the given locale.
Future<void> pumpWithL10n(
  WidgetTester tester,
  Widget child, {
  Locale locale = const Locale('zh'),
}) async {
  await tester.pumpWidget(l10nApp(child, locale: locale));
}
