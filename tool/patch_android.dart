// ignore_for_file: avoid_print
import 'dart:io';

const _permissions = <String, String>{
  'android.permission.INTERNET': '',
  'android.permission.READ_MEDIA_AUDIO': '',
  'android.permission.READ_EXTERNAL_STORAGE': ' android:maxSdkVersion="32"',
  'android.permission.WRITE_EXTERNAL_STORAGE': ' android:maxSdkVersion="29"',
  'android.permission.WAKE_LOCK': '',
  'android.permission.FOREGROUND_SERVICE': '',
  'android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK': '',
  'android.permission.POST_NOTIFICATIONS': '',
};

const _serviceBlock = '''
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
    ''';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('android/ folder not found. Run scripts/setup.sh first.');
    exit(1);
  }
  _patchManifest(manifest);
  _patchMainActivity();
  _patchAppGradle();
  _cleanRootGradle();
  _patchPubCachePlugins();
  print('Android project and pub-cache plugins patched for Nami.');
}

void _patchManifest(File file) {
  var text = file.readAsStringSync();
  final manifestTag = RegExp(r'<manifest[^>]*>').firstMatch(text);
  if (manifestTag == null || !text.contains('</application>')) {
    stderr.writeln('Unexpected AndroidManifest.xml layout.');
    exit(1);
  }

  final permissionLines = StringBuffer();
  _permissions.forEach((name, extra) {
    if (!text.contains('"$name"')) {
      permissionLines
          .write('\n    <uses-permission android:name="$name"$extra />');
    }
  });
  if (permissionLines.isNotEmpty) {
    final tag = manifestTag.group(0)!;
    text = text.replaceFirst(tag, '$tag${permissionLines.toString()}');
  }

  if (!text.contains('android:requestLegacyExternalStorage="true"')) {
    text = text.replaceFirst(
      '<application',
      '<application\n        android:requestLegacyExternalStorage="true"',
    );
  }

  if (!text.contains('com.ryanheise.audioservice.AudioService')) {
    text = text.replaceFirst(
        '</application>', '$_serviceBlock</application>');
  }

  text = text.replaceFirst('android:label="nami"', 'android:label="Nami"');
  file.writeAsStringSync(text);
}

void _patchMainActivity() {
  final root = Directory('android/app/src/main');
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) =>
          f.path.endsWith('MainActivity.kt') ||
          f.path.endsWith('MainActivity.java'))
      .toList();
  if (files.isEmpty) {
    stderr.writeln('MainActivity not found.');
    exit(1);
  }
  for (final file in files) {
    var text = file.readAsStringSync();
    text = text.replaceAll(
      'io.flutter.embedding.android.FlutterActivity',
      'com.ryanheise.audioservice.AudioServiceActivity',
    );
    text = text.replaceAll('FlutterActivity', 'AudioServiceActivity');
    file.writeAsStringSync(text);
  }
}

void _patchAppGradle() {
  for (final path in [
    'android/app/build.gradle',
    'android/app/build.gradle.kts',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = text.replaceAll(
      RegExp(r'minSdk\s*=?\s*flutter\.minSdkVersion'),
      'minSdk = 21',
    );
    text = text.replaceAll(
      RegExp(r'minSdkVersion\s+flutter\.minSdkVersion'),
      'minSdkVersion 21',
    );
    file.writeAsStringSync(text);
  }
}

void _cleanRootGradle() {
  for (final path in ['android/build.gradle', 'android/build.gradle.kts']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = text.replaceAll(RegExp(r'// namiNamespaceFix[\s\S]*'), '').trim();
    file.writeAsStringSync('$text\n');
  }
}

void _patchPubCachePlugins() {
  final env = Platform.environment;
  final candidates = <String>[
    if (env['PUB_CACHE'] != null) env['PUB_CACHE']!,
    if (env['HOME'] != null) '${env['HOME']}/.pub-cache',
    if (env['LOCALAPPDATA'] != null) '${env['LOCALAPPDATA']}/Pub/Cache',
  ];

  for (final rootPath in candidates) {
    final dir = Directory(rootPath);
    if (!dir.existsSync()) continue;

    final buildFiles = dir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) =>
            f.path.endsWith('/android/build.gradle') ||
            f.path.endsWith(r'\android\build.gradle'));

    for (final gradleFile in buildFiles) {
      var text = gradleFile.readAsStringSync();
      var modified = false;

      // 1. Align Java 1_8 / 11 with Kotlin 17 in plugin build.gradle files
      final updatedJava = text
          .replaceAll('JavaVersion.VERSION_1_8', 'JavaVersion.VERSION_17')
          .replaceAll('JavaVersion.VERSION_11', 'JavaVersion.VERSION_17')
          .replaceAll("jvmTarget = '1.8'", "jvmTarget = '17'")
          .replaceAll('jvmTarget = "1.8"', 'jvmTarget = "17"')
          .replaceAll("jvmTarget = '11'", "jvmTarget = '17'")
          .replaceAll('jvmTarget = "11"', 'jvmTarget = "17"');

      if (updatedJava != text) {
        text = updatedJava;
        modified = true;
      }

      // 2. Inject missing namespace from plugin's AndroidManifest.xml (e.g. on_audio_query_android)
      if (!text.contains('namespace')) {
        final manifestFile =
            File('${gradleFile.parent.path}/src/main/AndroidManifest.xml');
        if (manifestFile.existsSync()) {
          final manifestText = manifestFile.readAsStringSync();
          final pkgMatch =
              RegExp(r'package\s*=\s*"([^"]+)"').firstMatch(manifestText);
          if (pkgMatch != null) {
            final pkg = pkgMatch.group(1)!;
            text = text.replaceFirst(
              RegExp(r'android\s*\{'),
              'android {\n    namespace "$pkg"',
            );
            modified = true;
          }
        }
      }

      // 3. Ensure compileOptions uses Java 17 if missing inside on_audio_query_android
      if (gradleFile.path.contains('on_audio_query') &&
          !text.contains('compileOptions')) {
        text = text.replaceFirst(
          RegExp(r'android\s*\{'),
          'android {\n    compileOptions {\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n    }',
        );
        modified = true;
      }

      if (modified) {
        gradleFile.writeAsStringSync(text);
        print('Patched plugin gradle: ${gradleFile.path}');
      }
    }
  }
}
