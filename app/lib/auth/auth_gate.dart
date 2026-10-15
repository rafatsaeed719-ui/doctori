import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/admin_home.dart';
import '../core/l10n.dart';
import '../core/lookups.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../doctor/doctor_home.dart';
import '../main.dart';
import '../patient/patient_home.dart';
import 'auth_screens.dart';

/// Decides what to show: welcome/login when signed out, the right home per role when signed in.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> _sub;

  @override
  void initState() {
    super.initState();
    AppState.loadAppName();
    _sub = supa.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) AppState.context = const {};
      if (data.event == AuthChangeEvent.passwordRecovery) {
        navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => const NewPasswordScreen()));
      }
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = supa.auth.currentSession;
    if (session == null) return const WelcomeScreen();
    return RoleRouter(key: ValueKey(session.user.id));
  }
}

class RoleRouter extends StatefulWidget {
  const RoleRouter({super.key});
  @override
  State<RoleRouter> createState() => _RoleRouterState();
}

class _RoleRouterState extends State<RoleRouter> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() async {
    final res = await rpc('get_my_context');
    await Lookups.ensure();
    final ctx = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
    AppState.context = ctx;
    final locale = ctx['locale'];
    if (locale is String) L10n.set(locale);
    return ctx;
  }

  void _refresh() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: LoadingView());
        }
        if (snap.hasError || (snap.data?.isEmpty ?? true)) {
          return Scaffold(
            body: ErrorView(
              message: snap.hasError
                  ? friendlyError(snap.error!)
                  : tr('لم نجد بيانات حسابك. سجّل الخروج ثم الدخول مرة أخرى.',
                      'Account data not found. Log out and in again.'),
              onRetry: _refresh,
              details: snap.hasError ? errorDetails(snap.error!) : 'empty context',
            ),
            bottomNavigationBar: SafeArea(
              child: TextButton(onPressed: () => supa.auth.signOut(), child: Text(tr('تسجيل الخروج', 'Log out'))),
            ),
          );
        }
        final ctx = snap.data!;
        if (ctx['is_suspended'] == true) return const _SuspendedScreen();
        return switch (ctx['role']) {
          'admin' => const AdminHome(),
          'doctor' => DoctorHome(onContextChanged: _refresh),
          _ => const PatientHome(),
        };
      },
    );
  }
}

class _SuspendedScreen extends StatelessWidget {
  const _SuspendedScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: EmptyView(
          icon: Icons.block,
          title: tr('تم تعليق هذا الحساب', 'This account is suspended'),
          subtitle: tr('تواصل مع إدارة المنصة لمعرفة السبب.', 'Contact the platform administration for details.'),
          action: OutlinedButton(onPressed: () => supa.auth.signOut(), child: Text(tr('تسجيل الخروج', 'Log out'))),
        ),
      );
}
