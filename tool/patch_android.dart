// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  _patchManifest();
  _patchAppGradle();
  _patchPubCache();
  print('Nami Android patches applied: Removed legacy package attributes.');
}

void _patchManifest() {
  final file = File('android/app/src/main/AndroidManifest.xml');
  if (!file.existsSync()) return;
  var text = file.readAsStringSync();
  if (!text.contains('requestLegacyExternalStorage')) {
    text = text.replaceFirst('<application', '<application\n    android:requestLegacyExternalStorage="true"');
  }
  if (!text.contains('AudioService')) {
    text = text.replaceFirst('</application>', '''
        <service android:name="com.ryanheise.audioservice.AudioService" android:foregroundServiceType="mediaPlayback" android:exported="true">
            <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" android:exported="true">
            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>
        </receiver>
    </application>''');
  }
  file.writeAsStringSync(text);
}

void _patchAppGradle() {
  for (final path in ['android/app/build.gradle', 'android/app/build.gradle.kts']) {
    final file = File(path);
    if (!file.existsSync()) continue;
    var text = file.readAsStringSync();
    text = text
        .replaceAll(RegExp(r'minSdk\s*=?\s*.*'), 'minSdk = 21')
        .replaceAll(RegExp(r'compileSdk\s*=?\s*.*'), 'compileSdk = 36')
        .replaceAll(RegExp(r'targetSdk\s*=?\s*.*'), 'targetSdk = 36');
    file.writeAsStringSync(text);
  }
}

void _patchPubCache() {
  final home = Platform.environment['HOME'];
  if (home == null) return;
  final dir = Directory('$home/.pub-cache');
  if (!dir.existsSync()) return;

  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    // 1. Strip the forbidden 'package' attribute from Manifests and inject into build.gradle
    if (entity is File && entity.path.endsWith('AndroidManifest.xml')) {
      var text = entity.readAsStringSync();
      final pkgMatch = RegExp(r'package\s*=\s*"([^"]+)"').firstMatch(text);
      if (pkgMatch != null) {
        final pkg = pkgMatch.group(1)!;
        // Strip package attribute to satisfy AGP 8
        entity.writeAsStringSync(text.replaceAll(pkgMatch.group(0)!, ''));
        
        // Inject namespace into the corresponding build.gradle
        final gPath = entity.path.replaceAll('src/main/AndroidManifest.xml', 'build.gradle').replaceAll(r'src\main\AndroidManifest.xml', 'build.gradle');
        final gFile = File(gPath);
        if (gFile.existsSync()) {
          var gText = gFile.readAsStringSync();
          if (!gText.contains('namespace')) {
            gFile.writeAsStringSync(gText.replaceFirst('android {', 'android {\n    namespace "$pkg"'));
          }
        }
      }
    }
    
    // 2. Force Java 17 compatibility
    if (entity is File && entity.path.endsWith('build.gradle')) {
      var text = entity.readAsStringSync();
      var changed = false;
      
      if (!text.contains('compileOptions') && text.contains('android {')) {
        text = text.replaceFirst('android {', 'android {\n    compileOptions {\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17\n    }');
        changed = true;
      }
      
      if (text.contains('VERSION_1_8') || text.contains('VERSION_11') || text.contains("jvmTarget = '1.8'") || text.contains('jvmTarget = "11"')) {
        text = text.replaceAll('VERSION_1_8', 'VERSION_17').replaceAll('VERSION_11', 'VERSION_17')
            .replaceAll("jvmTarget = '1.8'", "jvmTarget = '17'").replaceAll('jvmTarget = "1.8"', 'jvmTarget = "17"')
            .replaceAll("jvmTarget = '11'", "jvmTarget = '17'").replaceAll('jvmTarget = "11"', 'jvmTarget = "17"');
        changed = true;
      }
      
      if (changed) {
        entity.writeAsStringSync(text);
      }
    }
  }
}
