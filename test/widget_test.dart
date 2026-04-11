import 'package:flutter_test/flutter_test.dart';
import 'package:lserial/app/app.dart';

void main() {
  testWidgets('communication tool shell smoke test', (tester) async {
    await tester.pumpWidget(const CommToolApp());
    await tester.pump();

    expect(find.text('连接方式'), findsOneWidget);
    expect(find.text('发送数据'), findsOneWidget);
  });
}
