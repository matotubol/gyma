import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'active_workout_screen.dart';
import 'check_in_sheet.dart';
import 'history_tab.dart';
import 'progress_tab.dart';
import 'coach_tab.dart';
import 'data_screen.dart';
import 'recovery_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  Future<void> _startOrResume() async {
    var workout = store.activeWorkout;
    if (workout == null) {
      final checkIn = await showModalBottomSheet<(Shift, Energy)>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => const CheckInSheet(),
      );
      if (checkIn == null) return;
      workout = store.startWorkout(checkIn.$1, checkIn.$2);
    }
    final Workout current = workout;
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ActiveWorkoutScreen(workout: current)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final active = store.activeWorkout != null;
        return Scaffold(
          appBar: AppBar(
              title: Text(['Gyma', 'Workouts', 'Coach'][_tab]),
              actions: [
                IconButton(
                    tooltip: 'Daily soreness',
                    icon: const Icon(Icons.accessibility_new),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const RecoveryScreen()))),
                IconButton(
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const DataScreen()))),
              ]),
          body: Column(children: [
            if (store.storageError != null)
              MaterialBanner(content: Text(store.storageError!), actions: [
                TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const DataScreen())),
                    child: const Text('Backup'))
              ]),
            Expanded(
                child: IndexedStack(
                    index: _tab,
                    children: const [ProgressTab(), HistoryTab(), CoachTab()])),
          ]),
          floatingActionButton: _tab == 2
              ? null
              : FloatingActionButton.extended(
                  onPressed: _startOrResume,
                  icon: Icon(
                      active ? Icons.timer_outlined : Icons.play_arrow_rounded),
                  label: Text(active ? 'Resume workout' : 'Start workout'),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.insights), label: 'Overview'),
              NavigationDestination(
                  icon: Icon(Icons.fitness_center), label: 'Workouts'),
              NavigationDestination(
                  icon: Icon(Icons.auto_awesome), label: 'Coach'),
            ],
          ),
        );
      },
    );
  }
}
