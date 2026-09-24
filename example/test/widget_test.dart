import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('demo builds', (tester) async {
    await tester.pumpWidget(const BlobEditorDemo());
    expect(find.text('blob editor'), findsOneWidget);
  });
}
