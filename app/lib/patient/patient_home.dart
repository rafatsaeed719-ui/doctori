import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/settings_screen.dart';
import '../core/avatar.dart';
import '../core/backgrounds.dart';
import '../core/l10n.dart';
import '../core/look3d.dart';
import '../core/supa.dart';
import '../core/widgets.dart';
import '../core/reminders.dart';
import 'booking_screens.dart';
import 'medical_file_screen.dart';
import 'meds_screen.dart';
import 'my_doctors_screen.dart';
import 'my_plan_screen.dart';
import '../common/announcements.dart';
import '../common/offers_screens.dart';
import '../doctor/rx_screens.dart';
import 'my_requests_screen.dart';
import 'search_screen.dart';

class PatientHome extends StatefulWidget {
  const PatientHome({super.key});
  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  int _tab = 0;

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    final accent = patientLook.accent;
    final pages = [
      _PatientDashboard(goTo: _go),
      const SearchScreen(),
      const MyDoctorsScreen(),
      const MyRequestsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: navIcon3D(Icons.home_rounded, accent),
              label: tr('الرئيسية', 'Home')),
          NavigationDestination(icon: const Icon(Icons.search), selectedIcon: navIcon3D(Icons.search, Tone.blue),
              label: tr('البحث', 'Search')),
          NavigationDestination(icon: const Icon(Icons.medical_services_outlined),
              selectedIcon: navIcon3D(Icons.medical_services, Tone.teal), label: tr('أطبائي', 'Doctors')),
          NavigationDestination(icon: const Icon(Icons.outbox_outlined), selectedIcon: navIcon3D(Icons.outbox, Tone.orange),
              label: tr('طلباتي', 'Requests')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: navIcon3D(Icons.person, Tone.pink),
              label: tr('حسابي', 'Account')),
        ],
      ),
    );
  }
}

const _tipsAr = [
  'اشرب 8 أكواب مياه على مدار اليوم، جسمك هيشكرك 💧',
  'مشي 20 دقيقة يومياً بيفرق جداً في صحة القلب والمزاج 🚶',
  'النوم الكويس من 7 لـ 8 ساعات أهم علاج مجاني 😴',
  'خد أدويتك في مواعيدها، وما تغيّرش الجرعة من غير ما تسأل دكتورك 💊',
  'نفَس عميق 5 مرات بيهدّي الأعصاب في دقيقة 🌿',
  'قلّل الملح والسكر، وزوّد الخضار والفاكهة في يومك 🥗',
  'اسأل دكتورك عن أي حاجة مش واضحة، مفيش سؤال صغير 🩺',
  'ابتسم! الضحك بيقوّي المناعة ويحسّن المزاج 😊',
  'افصل عن الموبايل ساعة قبل النوم عشان نومك يبقى أهدى 🌙',
  'شوية شمس الصبح مفيدين لفيتامين د وللمزاج ☀️',
];
const _tipsEn = [
  'Drink 8 glasses of water through the day 💧',
  'A 20-minute daily walk helps your heart and mood 🚶',
  '7–8 hours of good sleep is the best free medicine 😴',
  'Take your medicines on time and never change a dose without asking 💊',
  'Five deep breaths calm your nerves in a minute 🌿',
  'Less salt and sugar, more vegetables and fruit 🥗',
  'Ask your doctor anything that is unclear — no question is too small 🩺',
  'Smile! Laughter supports immunity and mood 😊',
  'Put the phone away an hour before bed for calmer sleep 🌙',
  'A little morning sun helps vitamin D and mood ☀️',
];

class _PatientDashboard extends StatelessWidget {
  const _PatientDashboard({required this.goTo});
  final void Function(int) goTo;

  Future<(int, int, int, int, int)> _counts() async {
    final docs = await rpcList('patient_my_doctors');
    final reqs = await rpcList('patient_my_requests');
    final meds = ((await rpc('list_medications')) as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final appts = (await rpc('patient_my_appointments')) as List? ?? const [];
    var followups = const <Map<String, dynamic>>[];
    try {
      followups = await rpcList('patient_followups');
    } catch (_) {/* older server */}
    // Keep phone reminders in step with the latest medicines, prescriptions and follow-up dates.
    Reminders.syncFollowups(followups);
    Reminders.sync(meds);
    final nextFollowups = followups.where((f) => f['status'] == 'scheduled' &&
        (DateTime.tryParse('${f['scheduled_at']}')?.isAfter(DateTime.now()) ?? false)).length;
    final activeMeds = meds.where((m) => m['is_active'] == true).length;
    final upcoming = appts.where((a) {
      final m = a as Map;
      return (m['status'] == 'pending' || m['status'] == 'confirmed') &&
          (DateTime.tryParse('${m['starts_at']}')?.isAfter(DateTime.now()) ?? false);
    }).length;
    return (docs.length, reqs.where((r) => r['status'] == 'pending').length, activeMeds, upcoming, nextFollowups);
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h >= 5 && h < 12) return tr('صباح الخير', 'Good morning');
    if (h >= 12 && h < 17) return tr('نهارك سعيد', 'Good afternoon');
    return tr('مساء الخير', 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final day = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    final tip = (L10n.isAr ? _tipsAr : _tipsEn)[day % _tipsAr.length];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PatternBackground(
        look: patientLook,
        calm: true,
        child: SafeArea(
          child: FutureView<(int, int, int, int, int)>(
            load: _counts,
            builder: (context, counts, reload) => RefreshList(
              onRefresh: reload,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                ValueListenableBuilder<Map<String, dynamic>>(
                  valueListenable: AppState.ctx,
                  builder: (context, ctx, _) {
                    final name = (ctx['full_name'] as String? ?? '').split(' ').first;
                    return GlassCard(
                      padding: const EdgeInsets.all(18),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          GestureDetector(
                            onTap: () => changeMyAvatar(context),
                            child: UserAvatar(url: ctx['avatar_url'] as String?, name: ctx['full_name'] as String?,
                                radius: 30, ring: patientLook.accent),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${_greeting()} 👋', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                              Text(name, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                            ]),
                          ),
                          ValueListenableBuilder<String>(
                            valueListenable: AppState.appName,
                            builder: (_, n, __) => Image.asset('assets/logo.png', width: 40, height: 40, semanticLabel: n),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        Text(
                          tr('أهلاً بيك في مساحتك الآمنة 💙\nهنا تتابع صحتك مع أطبائك بهدوء وخصوصية، وكل خطوة في علاجك محفوظة.',
                              'Welcome to your safe space 💙\nFollow your health with your doctors calmly and privately; every step is kept.'),
                          style: tt.bodyLarge?.copyWith(height: 1.6),
                        ),
                      ]),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [lighten(Tone.green, 0.75), lighten(Tone.sky, 0.78)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    const Icon3D(Icons.lightbulb, color: Tone.amber, size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('نصيحة اليوم', 'Tip of the day'),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1D4D3A))),
                        const SizedBox(height: 2),
                        Text(tip, style: const TextStyle(height: 1.5, color: Color(0xFF1D3B4A))),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                const AnnouncementsStrip(),
                const OffersStrip(),
                TileGrid(children: [
                  Tile3D(icon: Icons.search_rounded, color: Tone.blue, label: tr('ابحث عن طبيب', 'Find a doctor'),
                      subtitle: tr('بالتخصص أو الأقرب ليك', 'By specialty or nearby'), onTap: () => goTo(1)),
                  Tile3D(icon: Icons.medical_services_rounded, color: Tone.teal, label: tr('أطبائي', 'My doctors'),
                      subtitle: tr('${counts.$1} طبيب', '${counts.$1} doctors'), onTap: () => goTo(2)),
                  Tile3D(icon: Icons.outbox_rounded, color: Tone.orange, label: tr('طلباتي', 'My requests'),
                      badge: counts.$2, subtitle: tr('${counts.$2} بانتظار الرد', '${counts.$2} pending'),
                      onTap: () => goTo(3)),
                  Tile3D(icon: Icons.medication_rounded, color: Tone.green, label: tr('علاجي', 'My treatment'),
                      subtitle: tr('${counts.$3} دوا • تذكير بالمواعيد', '${counts.$3} medicines • reminders'),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MedsScreen()));
                        reload();
                      }),
                  Tile3D(icon: Icons.assignment_rounded, color: Tone.sky, label: tr('خطتي العلاجية', 'My treatment plan'),
                      badge: counts.$5,
                      subtitle: counts.$5 > 0
                          ? tr('${counts.$5} ميعاد متابعة', '${counts.$5} follow-ups')
                          : tr('المشكلة والهدف والمتابعة', 'Problem, goal, follow-ups'),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPlanScreen()));
                        reload();
                      }),
                  Tile3D(icon: Icons.local_offer_rounded, color: Tone.red, label: tr('عروض الأطباء', 'Doctors’ offers'),
                      subtitle: tr('عمليات وكشف وخدمات', 'Operations, visits, services'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OffersScreen()))),
                  Tile3D(icon: Icons.receipt_long_rounded, color: Tone.amber, label: tr('روشتاتي', 'My prescriptions'),
                      subtitle: tr('اطبعها أو ابعتها', 'Print or share'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPrescriptionsScreen()))),
                  Tile3D(icon: Icons.folder_shared_rounded, color: Tone.purple, label: tr('ملفي الطبي', 'My medical file'),
                      subtitle: tr('صور، فيديو، ملاحظات', 'Photos, videos, notes'),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicalFileScreen()))),
                  Tile3D(icon: Icons.event_note_rounded, color: Tone.indigo, label: tr('مواعيدي', 'My appointments'),
                      badge: counts.$4, subtitle: tr('${counts.$4} قادم', '${counts.$4} upcoming'),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => const MyAppointmentsScreen()));
                        reload();
                      }),
                  Tile3D(icon: Icons.person_rounded, color: Tone.pink, label: tr('حسابي', 'My account'),
                      subtitle: tr('الصورة والبيانات', 'Photo & details'), onTap: () => goTo(4)),
                  Tile3D(icon: Icons.emergency_rounded, color: Tone.red, label: tr('طوارئ 123', 'Emergency 123'),
                      subtitle: tr('اتصال بالإسعاف', 'Call ambulance'),
                      onTap: () => launchUrl(Uri(scheme: 'tel', path: '123'))),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
