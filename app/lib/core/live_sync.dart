import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supa.dart';

/// Live sync: the server sends a tiny "ping" whenever data this user works on changes
/// (a booking, a payment, the queue, a prescription…), and every open screen reloads by itself.
/// So what the secretary enters shows up on the doctor's phone straight away, and the other way round.
class LiveSync with WidgetsBindingObserver {
  LiveSync._();
  static final _i = LiveSync._();

  /// Bumps after each burst of changes. Screens listen and reload quietly.
  static final tick = ValueNotifier<int>(0);

  /// The scopes that changed in the last burst: bookings, queue, finance, medical, patients, inventory, center.
  static Set<String> lastScopes = const {};

  static RealtimeChannel? _channel;
  static Timer? _debounce;
  static Timer? _poll;
  static final _pending = <String>{};
  static bool _live = false;
  static bool _observing = false;

  static void start() {
    stop();
    final uid = supa.auth.currentUser?.id;
    if (uid == null) return;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(_i);
      _observing = true;
    }
    try {
      _channel = supa
          .channel('sync-$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'sync_pings',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (p) => _ping('${p.newRecord['scope'] ?? 'all'}'),
          )
          .subscribe((status, _) => _live = status == RealtimeSubscribeStatus.subscribed);
    } catch (_) {
      _live = false;
    }
    // Safety net: if live updates are cut (weak network), refresh every 30 seconds anyway.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_live) _ping('all');
    });
  }

  static void stop() {
    _poll?.cancel();
    _poll = null;
    _debounce?.cancel();
    _pending.clear();
    final c = _channel;
    _channel = null;
    _live = false;
    if (c != null) supa.removeChannel(c);
  }

  /// Many rows can change at once (e.g. saving a prescription); reload once per burst.
  static void _ping(String scope) {
    _pending.add(scope);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      lastScopes = Set.of(_pending);
      _pending.clear();
      tick.value++;
    });
  }

  /// Ask open screens to reload now (e.g. after this phone saved something).
  static void refreshNow() => _ping('all');

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the background: catch up on anything missed while asleep.
    if (state == AppLifecycleState.resumed && supa.auth.currentUser != null) _ping('all');
  }
}

/// Reloads [onChange] whenever synced data changes. For screens that load data themselves.
mixin LiveReload<T extends StatefulWidget> on State<T> {
  void onLiveChange();

  @override
  void initState() {
    super.initState();
    LiveSync.tick.addListener(_onTick);
  }

  void _onTick() {
    if (mounted) onLiveChange();
  }

  @override
  void dispose() {
    LiveSync.tick.removeListener(_onTick);
    super.dispose();
  }
}
