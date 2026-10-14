import 'package:flutter/material.dart';

import '../common/settings_screen.dart';
import '../core/l10n.dart';
import 'my_doctors_screen.dart';
import 'my_requests_screen.dart';
import 'search_screen.dart';

class PatientHome extends StatefulWidget {
  const PatientHome({super.key});
  @override
  State<PatientHome> createState() => _PatientHomeState();
}

class _PatientHomeState extends State<PatientHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const SearchScreen(),
      const MyDoctorsScreen(),
      const MyRequestsScreen(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.search), label: tr('البحث', 'Search')),
          NavigationDestination(icon: const Icon(Icons.medical_services_outlined),
              selectedIcon: const Icon(Icons.medical_services), label: tr('أطبائي', 'My doctors')),
          NavigationDestination(icon: const Icon(Icons.outbox_outlined),
              selectedIcon: const Icon(Icons.outbox), label: tr('طلباتي', 'Requests')),
          NavigationDestination(icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person), label: tr('حسابي', 'Account')),
        ],
      ),
    );
  }
}
