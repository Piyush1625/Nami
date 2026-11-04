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
  _patchRootGradleLazyJvmFix();
  print('Android project successfully patched for SDK 36 and lazy Java 17 enforcement.');
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
    text = text
        .replaceAll(RegExp(r'minSdk\s*=?\s*.*'), 'minSdk = 21')
        .replaceAll(RegExp(r'minSdkVersion\s+.*'), 'minSdkVersion 21')
        .replaceAll(RegExp(r'compileSdk\s*=?\s*.*'), 'compileSdk = 36')
        .replaceAll(RegExp(r'compileSdkVersion\s+.*'), 'compileSdkVersion 36')
        .replaceAll(RegExp(r'targetSdk\s*=?\s*.*'), 'targetSdk = 36')
        .replaceAll(RegExp(r'targetSdkVersion\s+.*'), 'targetSdkVersion 36');
    
    if (!text.contains('compileSdk')) {
      text = text.replaceFirst('android {', 'android {\n    compileSdk = 36\n');
    }
    file.writeAsStringSync(text);
  }
}

void _patchRootGradleLazyJvmFix() {
  for (final path in ['android/build.gradle.kts', 'android/build.gradle']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = text.replaceAll(RegExp(r'// namiLazyJvmFix[\s\S]*'), '').trim();
    
    const fixKts = '''\n
// namiLazyJvmFix
allprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            try {
                val compileOptions = android.javaClass.getMethod("getCompileOptions").invoke(android)
                compileOptions.javaClass.getMethod("getSourceCompatibility").invoke(compileOptions)
                // Force Java 17 compatibility on all subprojects/plugins
                compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
                compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
            } catch (_: Exception) {}
        }
    }
    tasks.withType(JavaCompile::class.java).configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile::class.java).configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
''';
    file.writeAsStringSync('$text$fixKts');
    break; // Patch root build.gradle / build.gradle.kts once
  }
}
