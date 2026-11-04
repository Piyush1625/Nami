// ignore_for_file: avoid_print
import 'dart:io';

void main() {
  _patchManifest();
  _patchAppGradle();
  _patchPubCache();
  print('Nami Android patches applied successfully.');
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
    if (entity is File && entity.path.endsWith('build.gradle')) {
      var text = entity.readAsStringSync();
      var changed = false;
      
      if (!text.contains('namespace') && entity.path.contains('on_audio_query')) {
        text = text.replaceFirst('android {', 'android {\n    namespace "com.lucasjosino.audio_query"');
        changed = true;
      }
      if (text.contains('VERSION_1_8') || text.contains('VERSION_11')) {
        text = text.replaceAll('VERSION_1_8', 'VERSION_17').replaceAll('VERSION_11', 'VERSION_17');
        changed = true;
      }
      if (changed) {
        entity.writeAsStringSync(text);
      }
    }
  }
}
