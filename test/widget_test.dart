import 'package:flutter_test/flutter_test.dart';

import 'package:video_editor/main.dart';

void main() {
  testWidgets('home screen renders', (tester) async {
    await tester.pumpWidget(const VideoEditorApp());
    expect(find.text('Video Editor'), findsWidgets);
    expect(find.text('Select Video'), findsOneWidget);
  });
}
