import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase configuration for the web build.
///
/// Values are injected at build time via `--dart-define` (see
/// `.github/workflows/deploy-cloudflare-pages.yml`). Only the API key is
/// secret-ish; the remaining identifiers are public project metadata.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: ''),
    appId: String.fromEnvironment('FIREBASE_APP_ID',
        defaultValue: '1:676641617260:web:11451b6ad7f20108dbb0a2'),
    messagingSenderId: String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID',
        defaultValue: '447745789348'),
    projectId: String.fromEnvironment('FIREBASE_PROJECT_ID',
        defaultValue: 'tracealot-f6ba9'),
    authDomain: String.fromEnvironment('FIREBASE_AUTH_DOMAIN',
        defaultValue: 'tracealot-f6ba9.firebaseapp.com'),
    storageBucket: String.fromEnvironment('FIREBASE_STORAGE_BUCKET',
        defaultValue: 'tracealot-f6ba9.firebasestorage.app'),
    measurementId: String.fromEnvironment('FIREBASE_MEASUREMENT_ID',
        defaultValue: ''),
  );
}
