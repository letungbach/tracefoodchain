# 07_DEPLOYMENT_GUIDE.md
## TraceALot Production Build, Multi-Platform Deployment & CI/CD Guide

**Target Platform:** [https://tracealot.com](https://tracealot.com)  
**Distribution Targets:** Cloudflare Pages (Web PWA), Google Play Store (Android AAB), Apple App Store (iOS IPA)  
**DevOps Automation:** GitHub Actions + Cloudflare Wrangler + Firebase CLI  
**Environment Standard:** Production Zero-Trust Configuration

---

## 1. Prerequisites & Toolchain Setup

Ensure the build environment has the following tool versions installed:

| Tool | Minimum Version | Installation / Verification Command |
| :--- | :--- | :--- |
| **Flutter SDK** | `>= 3.24.0` (Dart 3.5+) | `flutter --version` |
| **Node.js** | `>= 20.x LTS` | `node -v` |
| **Cloudflare Wrangler** | `>= 3.78.x` | `wrangler --version` |
| **Firebase CLI** | `>= 13.x` | `firebase --version` |
| **Java JDK (Android)** | OpenJDK 17 | `java -version` |
| **Xcode (iOS/macOS)** | Xcode 16.x | `xcodebuild -version` |

---

## 2. Flutter Web Production Build

### 2.1 Web Renderer Architecture
For GIS mapping (`google_maps_flutter_web`), polygon editing, and multi-layered charts, TraceALot utilizes CanvasKit / WebAssembly rendering for visual fidelity, precision, and performance.

### 2.2 Compilation Command
Execute the production build with `--dart-define` injection to prevent bundling raw `.env` files into public web bundles:

```bash
flutter build web \
  --release \
  --web-renderer canvaskit \
  --tree-shake-icons \
  --pwa-strategy offline-first \
  --dart-define=ENVIRONMENT=production \
  --dart-define=APP_DOMAIN=tracealot.com \
  --dart-define=FIREBASE_API_KEY="$PROD_FIREBASE_API_KEY" \
  --dart-define=FIREBASE_AUTH_DOMAIN="tracefoodchain.firebaseapp.com" \
  --dart-define=FIREBASE_PROJECT_ID="tracefoodchain" \
  --dart-define=FIREBASE_STORAGE_BUCKET="tracefoodchain.appspot.com" \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID="676641617260" \
  --dart-define=FIREBASE_APP_ID="1:676641617260:web:11451b6ad7f20108dbb0a2" \
  --dart-define=GOOGLE_MAPS_API_KEY="$PROD_GOOGLE_MAPS_WEB_KEY" \
  --dart-define=WHISP_API_URL="https://api.tracealot.com/v1/whisp"
```

### 2.3 Post-Build Web Processing
After compilation, prepare the SPA redirect and security header rules inside `build/web`:

```bash
# 1. SPA Fallback for Cloudflare Pages (Direct URL routing)
echo "/*    /index.html   200" > build/web/_redirects

# 2. Strict Security Headers and Caching Policies
cat << 'EOF' > build/web/_headers
/*
  X-Frame-Options: SAMEORIGIN
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: geolocation=(self), camera=(self), microphone=()
  Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
  Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://maps.googleapis.com https://apis.google.com https://www.gstatic.com; connect-src 'self' https://*.firebaseio.com https://*.googleapis.com https://*.cloudfunctions.net https://api.tracealot.com https://cdn.tracealot.com wss://*.firebaseio.com; img-src 'self' data: blob: https://*.googleapis.com https://*.gstatic.com https://cdn.tracealot.com https://firebasestorage.googleapis.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; worker-src 'self' blob:;

/canvaskit/*
  Cache-Control: public, max-age=31536000, immutable

/assets/*
  Cache-Control: public, max-age=2592000

/flutter.js
  Cache-Control: public, max-age=3600, must-revalidate

/index.html
  Cache-Control: no-cache, no-store, must-revalidate
EOF
```

---

## 3. Android Production Build & Release

### 3.1 Keystore & Signing Configuration
Ensure a secure release keystore exists. Configure `android/key.properties`:

```properties
storePassword=SECURE_STORE_PASSWORD
keyPassword=SECURE_KEY_PASSWORD
keyAlias=tracealot-release
storeFile=/path/to/tracealot_release.keystore
```

### 3.2 Compilation Command
Generate a signed Google Play App Bundle (AAB):

```bash
flutter build appbundle \
  --release \
  --obfuscate \
  --split-debug-info=./build/app/outputs/symbols \
  --dart-define=ENVIRONMENT=production \
  --dart-define=GOOGLE_MAPS_API_KEY="$PROD_GOOGLE_MAPS_ANDROID_KEY"
```

---

## 4. iOS Production Build & Release

1. Verify bundle identifier is configured as `com.tracealot.app`.
2. Ensure `ios/Runner/GoogleService-Info.plist` is linked to the production Firebase project.
3. Build signed IPA archive:
```bash
flutter build ipa \
  --release \
  --obfuscate \
  --split-debug-info=./build/ios/symbols \
  --export-options-plist=ios/ExportOptions.plist
```

---

## 5. Firebase Production Rules & Functions Deployment

Deploy rules and serverless compute pipelines directly using the Firebase CLI:

```bash
# 1. Login to Firebase CLI with Service Account or OAuth
firebase use production-project-id

# 2. Deploy Firestore Security Rules & Indexes
firebase deploy --only firestore:rules,firestore:indexes

# 3. Deploy Cloud Storage Security Rules
firebase deploy --only storage

# 4. Deploy Cloud Functions (europe-west3)
firebase deploy --only functions
```

---

## 6. Automated GitHub Actions CI/CD Pipeline

Create `.github/workflows/deploy_production.yml` to automate all testing, building, and deployment to `tracealot.com`:

```yaml
name: TraceALot Production CI/CD Pipeline

on:
  push:
    branches: [main]
    tags: ['v*.*.*']

concurrency:
  group: production-deployment
  cancel-in-progress: false

jobs:
  validate_and_test:
    name: Code Quality & Unit Tests
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Setup Flutter 3.24.x
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.3'
          channel: 'stable'
          cache: true

      - name: Install Dependencies
        run: flutter pub get

      - name: Validate Localization Files
        run: flutter gen-l10n

      - name: Run Static Analysis
        run: flutter analyze --no-fatal-infos

      - name: Run Unit & Regression Tests
        run: flutter test --coverage

  deploy_web_cloudflare:
    name: Build & Deploy Web to Cloudflare Pages (app.tracealot.com)
    needs: validate_and_test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Setup Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.3'
          channel: 'stable'
          cache: true

      - name: Compile Flutter Web Release
        run: |
          flutter build web --release --web-renderer canvaskit \
            --tree-shake-icons \
            --dart-define=ENVIRONMENT=production \
            --dart-define=APP_DOMAIN=tracealot.com \
            --dart-define=FIREBASE_API_KEY="${{ secrets.PROD_FIREBASE_API_KEY }}" \
            --dart-define=GOOGLE_MAPS_API_KEY="${{ secrets.PROD_GOOGLE_MAPS_WEB_KEY }}"
          
          # Inject Cloudflare Pages routing and headers
          echo "/*    /index.html   200" > build/web/_redirects
          cat << 'EOF' > build/web/_headers
          /*
            X-Frame-Options: SAMEORIGIN
            X-Content-Type-Options: nosniff
            Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
          /index.html
            Cache-Control: no-cache, no-store, must-revalidate
          /canvaskit/*
            Cache-Control: public, max-age=31536000, immutable
          EOF

      - name: Deploy to Cloudflare Pages
        uses: cloudflare/pages-action@v1
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          projectName: 'tracealot-app'
          directory: 'build/web'
          gitHubToken: ${{ secrets.GITHUB_TOKEN }}

  deploy_firebase_rules:
    name: Deploy Firebase Security Rules & Indexes
    needs: validate_and_test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Deploy Firebase Rules
        uses: w9jds/firebase-action@master
        with:
          args: deploy --only firestore:rules,firestore:indexes,storage
        env:
          GCP_SA_KEY: ${{ secrets.FIREBASE_SERVICE_ACCOUNT_KEY }}
```
