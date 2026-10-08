import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'active_workout_screen.dart';
import 'check_in_sheet.dart';
import 'history_tab.dart';
import 'progress_tab.dart';

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
          appBar: AppBar(title: Text(_tab == 0 ? 'Gyma' : 'Progress')),
          body: _tab == 0 ? const HistoryTab() : const ProgressTab(),
          floatingActionButton: _tab != 0
              ? null
              : FloatingActionButton.extended(
                  onPressed: _startOrResume,
                  icon: Icon(active ? Icons.timer_outlined : Icons.play_arrow_rounded),
                  label: Text(active ? 'Resume workout' : 'Start workout'),
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.fitness_center), label: 'Workouts'),
              NavigationDestination(icon: Icon(Icons.insights), label: 'Progress'),
            ],
          ),
        );
      },
    );
  }
}
