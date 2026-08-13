import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/strings.dart';
import 'screens/home_shell.dart';
import 'services/config.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Off by default — the app is fully functional on local mock state with
  // no credentials. Supplying SUPABASE_URL/SUPABASE_ANON_KEY via
  // --dart-define initializes the client so lib/services/supabase_repositories.dart
  // has something to talk to once it's wired into AppState (see app/README.md).
  if (QamarConfig.useSupabase) {
    await Supabase.initialize(url: QamarConfig.supabaseUrl, anonKey: QamarConfig.supabaseAnonKey);
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const QamarApp(),
    ),
  );
}

class QamarApp extends StatelessWidget {
  const QamarApp({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = context.select<AppState, AppLang>((s) => s.lang);
    return MaterialApp(
      title: 'Qamar',
      debugShowCheckedModeBanner: false,
      theme: buildQamarTheme(),
      locale: Locale(lang.code),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: lang.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const HomeShell(),
    );
  }
}
