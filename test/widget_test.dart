import 'package:flutter_test/flutter_test.dart';
import 'package:kot_app/main.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KotmaleApp());
    expect(find.byType(KotmaleApp), findsOneWidget);
  });
}
