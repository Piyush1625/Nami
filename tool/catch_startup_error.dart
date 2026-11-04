// ignore_for_file: avoid_print
// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  final file = File('lib/main.dart');
  if (!file.existsSync()) return;
  var text = file.readAsStringSync();
  
  if (text.contains('namiErrorCatcher')) {
    print('Already patched.');
    return;
  }
  
  if (text.contains('void main() async {')) {
    text = text.replaceFirst('void main() async {', 'Future<void> namiOriginalMain() async {');
  } else if (text.contains('Future<void> main() async {')) {
    text = text.replaceFirst('Future<void> main() async {', 'Future<void> namiOriginalMain() async {');
  } else if (text.contains('void main() {')) {
    text = text.replaceFirst('void main() {', 'Future<void> namiOriginalMain() async {');
  } else if (text.contains('void main() =>')) {
    text = text.replaceFirst('void main() =>', 'Future<void> namiOriginalMain() async =>');
  } else {
    print('Could not find main function signature.');
    return;
  }
  
  text += '''\n
// namiErrorCatcher
import 'dart:async';

void main() {
  runZonedGuarded(() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await namiOriginalMain();
    } catch (e, st) {
      runApp(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.red,
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'STARTUP ERROR:\\n\\n\$e\\n\\n\$st',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      );
    }
  }, (e, st) {
    runApp(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.red,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(
                'UNCAUGHT ERROR:\\n\\n\$e\\n\\n\$st',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  });
}
''';

  file.writeAsStringSync(text);
  print('main.dart successfully patched with global error catcher!');
}
