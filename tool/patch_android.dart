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
  _patchRootGradleNamespaceFix();
  print('Android project patched for Nami.');
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

void _patchRootGradleNamespaceFix() {
  final groovy = File('android/build.gradle');
  if (groovy.existsSync()) {
    var text = groovy.readAsStringSync();
    text = text.replaceAll(RegExp(r'// namiNamespaceFix[\s\S]*'), '').trim();
    const fix = '''\n
// namiNamespaceFix
allprojects {
    tasks.withType(org.gradle.api.tasks.compile.JavaCompile).configureEach {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    tasks.withType(org.jetbrains.kotlin.gradle.tasks.KotlinCompile).configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
}
subprojects {
    plugins.withId("com.android.library") {
        project.android {
            if (namespace == null) {
                namespace project.group.toString()
            }
        }
    }
}
''';
    groovy.writeAsStringSync('$text$fix');
  }

  final kts = File('android/build.gradle.kts');
  if (kts.existsSync()) {
    var text = kts.readAsStringSync();
    text = text.replaceAll(RegExp(r'// namiNamespaceFix[\s\S]*'), '').trim();
    const fix = '''\n
// namiNamespaceFix
allprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
    }
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
}
subprojects {
    pluginManager.withPlugin("com.android.library") {
        val androidExt = extensions.findByName("android")
        if (androidExt != null) {
            try {
                val getNs = androidExt.javaClass.getMethod("getNamespace")
                val setNs = androidExt.javaClass.getMethod("setNamespace", String::class.java)
                if (getNs.invoke(androidExt) == null) {
                    setNs.invoke(androidExt, project.group.toString())
                }
            } catch (e: Exception) {}
        }
    }
}
''';
    kts.writeAsStringSync('$text$fix');
  }
}
