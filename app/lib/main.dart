import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/strings.dart';
import 'screens/home_shell.dart';
import 'services/auth_service.dart';
import 'services/config.dart';
import 'services/supabase_repositories.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Off by default — the app is fully functional on local state with no
  // credentials. Supplying SUPABASE_URL and SUPABASE_ANON_KEY via
  // --dart-define turns on persistence; everything below degrades to the
  // offline behaviour if any of it fails, because failing to reach a backend
  // must never be the reason someone cannot use the app.
  AppState state;
  if (QamarConfig.useSupabase) {
    state = await _backedState();
  } else {
    state = AppState();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => state,
      child: const QamarApp(),
    ),
  );
}

/// Brings up Supabase, ensures there is a user, and hands AppState its
/// repositories. Anonymous sign-in comes first so a new user has an identity —
/// and therefore rows they own under RLS — before answering a single question;
/// linking Apple or Google later keeps the same id and the same data.
Future<AppState> _backedState() async {
  try {
    await Supabase.initialize(
      url: QamarConfig.supabaseUrl,
      anonKey: QamarConfig.supabaseAnonKey,
    );
    final client = Supabase.instance.client;
    final user = await AuthService(client).ensureSignedIn();

    return AppState(
      profileRepo: SupabaseProfileRepository(client),
      mealRepo: SupabaseMealRepository(client),
      walletRepo: SupabaseWalletRepository(client),
      userId: user.id,
    );
  } catch (e) {
    // No network, anonymous sign-ins not enabled, bad keys: run offline
    // rather than showing a dead app.
    debugPrint('Qamar: continuing without a backend — $e');
    return AppState();
  }
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
