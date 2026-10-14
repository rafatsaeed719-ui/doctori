import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'core/config.dart';
import 'core/l10n.dart';
import 'core/theme.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);
  }
  runApp(const DoctoriApp());
}

class DoctoriApp extends StatelessWidget {
  const DoctoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: L10n.locale,
      builder: (context, locale, _) => MaterialApp(
        // Rebuild the whole tree when the language changes so every tr() re-evaluates.
        key: ValueKey(locale.languageCode),
        navigatorKey: navigatorKey,
        title: 'دكتوري',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        locale: locale,
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: AppConfig.isConfigured ? const AuthGate() : const _NotConfigured(),
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'هذه النسخة غير مربوطة بالسيرفر.\nThis build is missing its server settings (env/doctori.json).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}
