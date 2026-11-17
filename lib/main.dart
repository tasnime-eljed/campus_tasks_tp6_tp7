import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'providers/connectivity_provider.dart';
import 'providers/queue_provider.dart';
import 'repositories/queue_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/queue_screen.dart';
import 'screens/update_password_screen.dart';
import 'services/connectivity_service.dart';
import 'services/geolocation_service.dart';

const supabaseUrl = 'https://swccmnemljwtbxcdspqf.supabase.co';
const supabaseAnonKey = 'sb_publishable_D0JU4M4Ej4p1RThA1ICtGA_sCzu_nrM';
final passwordRecoveryPending = ValueNotifier<bool>(false);

bool _isPasswordRecoveryUri(Uri uri) {
  for (final value in [uri.query, uri.fragment]) {
    if (value.isEmpty) continue;
    try {
      final parameters = Uri.splitQueryString(value.replaceFirst(RegExp(r'^[?#]'), ''));
      if (parameters['type'] == 'recovery') return true;
    } on FormatException {
      // Ignore URL fragments that are not query parameters.
    }
  }
  return false;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb && _isPasswordRecoveryUri(Uri.base)) {
    passwordRecoveryPending.value = true;
  }
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  final supabase = Supabase.instance.client;
  // Capture the recovery event before the widget tree subscribes to the auth stream.
  supabase.auth.onAuthStateChange.listen((state) {
    if (state.event == AuthChangeEvent.passwordRecovery) {
      passwordRecoveryPending.value = true;
    } else if (state.event == AuthChangeEvent.signedOut ||
        (passwordRecoveryPending.value && state.event == AuthChangeEvent.userUpdated)) {
      passwordRecoveryPending.value = false;
    }
  });
  final repository = QueueRepository(supabase);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ConnectivityProvider(ConnectivityService(supabase))..initialize(),
        ),
        ChangeNotifierProvider(
          create: (_) => QueueProvider(repository, GeolocationService()),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Waiting Room',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const AuthGate(),
  );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return ValueListenableBuilder<bool>(
      valueListenable: passwordRecoveryPending,
      builder: (context, isPasswordRecovery, _) {
        if (isPasswordRecovery) return const UpdatePasswordScreen();
        return StreamBuilder<AuthState>(
          stream: auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session = snapshot.data?.session ?? auth.currentSession;
            if (session == null) return const AuthScreen();
            return FutureBuilder<Map<String, dynamic>?>(
              future: Supabase.instance.client
                  .from('user_profiles')
                  .select('display_name, role, status')
                  .eq('id', session.user.id)
                  .maybeSingle(),
              builder: (context, profileSnapshot) {
                if (profileSnapshot.connectionState != ConnectionState.done) {
                  return const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  );
                }
                if (profileSnapshot.hasError || profileSnapshot.data == null) {
                  return _AccountMessage(
                    message: 'Profil introuvable. Appliquez le script SQL fourni puis reconnectez-vous.',
                    onSignOut: () => auth.signOut(),
                    onRefresh: () => auth.refreshSession(),
                  );
                }
                final profile = profileSnapshot.data!;
                if (profile['status'] != 'approved') {
                  return _AccountMessage(
                    message: 'Votre compte est en attente d’approbation par un administrateur.',
                    onSignOut: () => auth.signOut(),
                    onRefresh: () => auth.refreshSession(),
                  );
                }
                return QueueScreen(
                  displayName: profile['display_name'] as String? ?? '',
                  isAdmin: profile['role'] == 'admin',
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AccountMessage extends StatelessWidget {
  const _AccountMessage({
    required this.message,
    required this.onSignOut,
    required this.onRefresh,
  });

  final String message;
  final Future<void> Function() onSignOut;
  final Future<dynamic> Function() onRefresh;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRefresh,
              child: const Text('Actualiser le statut'),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: onSignOut, child: const Text('Déconnexion')),
          ],
        ),
      ),
    ),
  );
}
