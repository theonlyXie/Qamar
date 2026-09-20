import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'l10n/strings.dart';
import 'screens/home_shell.dart';
import 'services/ai_gateway.dart';
import 'services/auth_service.dart';
import 'services/device_prefs.dart';
import 'services/dictation.dart';
import 'services/nudger.dart';
import 'services/config.dart';
import 'services/payments.dart';
import 'services/supabase_repositories.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';
import 'widgets/quick_invoke_binder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Off by default — the app is fully functional on local state with no
  // credentials. Supplying SUPABASE_URL and SUPABASE_ANON_KEY via
  // --dart-define turns on persistence; everything below degrades to the
  // offline behaviour if any of it fails, because failing to reach a backend
  // must never be the reason someone cannot use the app.
  // Dictation is on-device and needs no configuration, so it is always
  // available to try; it reports honestly if the platform cannot do it.
  final dictation = Dictation();

  AppState state;
  if (QamarConfig.useSupabase) {
    state = await _backedState(dictation);
  } else {
    state = AppState(ai: _gatewayIfConfigured(null), dictation: dictation, prefs: SharedDevicePrefs(), nudger: LocalNudger());
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
Future<AppState> _backedState(Dictation dictation) async {
  try {
    await Supabase.initialize(
      url: QamarConfig.supabaseUrl,
      anonKey: QamarConfig.supabaseAnonKey,
    );
    final client = Supabase.instance.client;
    final auth = AuthService(client);
    final user = await auth.ensureSignedIn();

    return AppState(
      profileRepo: SupabaseProfileRepository(client),
      mealRepo: SupabaseMealRepository(client),
      waterRepo: SupabaseWaterRepository(client),
      walletRepo: SupabaseWalletRepository(client),
      ai: _gatewayIfConfigured(client),
      billing: _billingIfConfigured(client),
      dictation: dictation,
      auth: auth,
      userId: user.id,
      prefs: SharedDevicePrefs(),
      nudger: LocalNudger(),
    );
  } catch (e) {
    // No network, anonymous sign-ins not enabled, bad keys: run offline
    // rather than showing a dead app.
    debugPrint('Qamar: continuing without a backend — $e');
    return AppState(dictation: dictation, prefs: SharedDevicePrefs(), nudger: LocalNudger());
  }
}

/// The real assistant, or null.
///
/// Null is deliberate and visible: with no gateway the app says it is not
/// connected rather than replying from a script. The gateway is called with
/// the user's own access token, so it can check who is asking and refuse a
/// blocked profile server-side.
AiGateway? _gatewayIfConfigured(SupabaseClient? client) {
  if (!QamarConfig.useAiGateway || client == null) return null;
  return HttpAiGateway(
    baseUrl: QamarConfig.aiGatewayUrl,
    authTokenProvider: () => client.auth.currentSession?.accessToken ?? '',
  );
}

BillingGateway? _billingIfConfigured(SupabaseClient? client) {
  if (!QamarConfig.useBilling || client == null) return null;
  return HttpBillingGateway(
    baseUrl: QamarConfig.billingUrl,
    authTokenProvider: () => client.auth.currentSession?.accessToken ?? '',
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
      home: const QuickInvokeBinder(child: HomeShell()),
    );
  }
}
