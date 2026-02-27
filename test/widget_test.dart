import 'package:flutter_test/flutter_test.dart';
import 'package:catat_kelas/app/school_finance_app.dart';

void main() {
  testWidgets('main shell renders finance dashboard',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        const SchoolFinanceApp(firebaseEnabled: false, repository: null));

    expect(find.text('Ringkasan Kas'), findsOneWidget);
    expect(find.text('Total Pemasukan'), findsOneWidget);
  });
}
