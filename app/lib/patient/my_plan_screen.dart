import 'package:flutter/material.dart';

import '../core/l10n.dart';
import '../doctor/case_plan_screens.dart';

/// Patient: my treatment plans (problem, where, goal, measurements, course) and follow-up dates.
class MyPlanScreen extends StatelessWidget {
  const MyPlanScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('خطتي العلاجية', 'My treatment plan')),
          bottom: TabBar(tabs: [
            Tab(icon: const Icon(Icons.assignment_rounded), text: tr('حالتي وخطتي', 'My plan')),
            Tab(icon: const Icon(Icons.event_repeat_rounded), text: tr('مواعيد المتابعة', 'Follow-ups')),
          ]),
        ),
        body: const TabBarView(children: [CasePlansView(), FollowupsView()]),
      ),
    );
  }
}
