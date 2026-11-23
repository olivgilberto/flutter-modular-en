import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_tasks_app/bootstrap/app_config.dart';
import 'package:mobile_tasks_app/bootstrap/firebase_options.dart';

void main() {
  // In the public copy, no flavor has a Firebase project: the boot goes on
  // without it. After `flutterfire configure` (chapter 38), this test goes
  // back to checking each flavor's projectId, as in the book.
  test('without the Firebase files, no flavor has options', () {
    for (final flavor in Flavor.values) {
      expect(firebaseOptionsFor(flavor), isNull);
    }
  });
}
