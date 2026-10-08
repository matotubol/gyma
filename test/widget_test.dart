import 'package:flutter_test/flutter_test.dart';
import 'package:gyma/main.dart';

void main() {
  testWidgets('home screen renders', (tester) async {
    await tester.pumpWidget(const GymaApp());
    expect(find.text('Gyma'), findsOneWidget);
    expect(find.text('No workouts yet'), findsOneWidget);
  });
}
