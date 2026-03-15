import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:robot_controller/main.dart';

void main() {
  testWidgets('renders login screen when not authenticated', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RobotControllerApp(isAuthenticated: false));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, 'Login'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Server IP / Host'), findsOneWidget);
  });
}
