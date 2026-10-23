# AI 모닝 브리핑

해외 AI 소식과 개발 문서를 한국어 세 줄로 읽는 Android 앱입니다. 별도 백엔드, 외부 DB, 로그인, 광고가 없습니다. 사용자가 자신의 Google Gemini API 키를 등록하며, 모든 설정·학습 기록·요약 캐시는 기기에 저장합니다.

## 사용하기

GitHub Releases에서 **arm64 APK**를 내려받아 Android 7.0(API 24) 이상 arm64 기기에 설치하세요. 최초 실행 시 3단계 안내에 따라 Google AI Studio에서 발급한 API 키를 등록합니다. 지역·계정별 사용 가능 여부와 무료 제공량은 Google 정책에 따라 달라지며, 영구 무료를 보장하지 않습니다.

- 오늘의 최신 소식 10개를 모아, 저장된 요약을 먼저 보여줍니다.
- API 키의 접두사나 길이는 제한하지 않습니다. 앞뒤 공백을 제거하고 빈 입력만 안내하며, Google 모델 목록 조회의 성공 여부로 키와 사용 가능한 텍스트 Flash 모델을 확인한 후 저장합니다.
- 새로운 소식은 Google 모델 목록에서 확인한 텍스트 Flash 모델에 한 번으로 묶어 요청합니다. `gemini-flash-latest`를 우선하며, 해당 별칭이 없으면 목록에서 실제로 제공되는 안정 버전 Flash 모델을 선택합니다. 제목, 발췌문, 출처, 기사 식별자가 Google로 전송됩니다. 전문을 수집하거나 추측하지 않습니다.
- 키 확인은 콘텐츠를 생성하지 않는 모델 목록 조회로 분리합니다. 요약 생성만 65초 간격 제한을 적용하므로 키 확인 직후 첫 요약을 요청할 수 있습니다. 계정별 무료 한도는 더 낮을 수 있으며 429 응답을 받으면 추가 대기합니다.
- 키 확인 성공이 요약 생성의 지역·권한·할당량을 보장하지는 않습니다. Google 오류는 HTTP 코드와 안전한 상태 코드로 구분해 안내하며 원문 오류 본문이나 키는 표시하지 않습니다.
- 요약이 없거나 실패하면 원문 제목·발췌문을 보여줍니다. 피드에 없는 정보를 완전한 기사 요약으로 표시하지 않습니다.
- 설정에서 소스를 끄거나 공개 HTTPS RSS/Atom 피드를 추가할 수 있습니다. 변경 후 브리핑을 새로고침하세요.
- 연속 학습은 기기 현지 날짜 기준 하루 한 번만 증가합니다.
- 알림은 설정에서 직접 켭니다. Android 13+ 알림 권한과 Android 12+ 정확한 알림 권한을 요청하며, 정확한 알림 권한이 없으면 대략적인 시간에 알립니다. 기본 시간은 오전 8시입니다. 기기 절전 정책에 따라 지연될 수 있습니다.

## 개발

도구 버전: **Flutter 3.47.7 / Dart 3.13.5**, JDK 21, Android SDK 36, NDK `28.2.13676358`, Gradle 9.3.1, AGP 9.1.0. Flutter 버전은 `.flutter-version`, 의존성은 `pubspec.lock`에 고정합니다. Android 이외 플랫폼은 구성하지 않았습니다.

클라우드 환경에서는 먼저 다음을 실행하세요.

```bash
source /workspace/toolchains/env.sh
cd /workspace/AI-Trend-Dev-Docs-Briefing-App
```

일반 개발 환경에서는 Flutter, JDK, Android SDK를 설치한 뒤 다음을 실행하세요.

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze --fatal-infos
flutter test
dart run tool/feed_smoke.dart
flutter run -d <android-device-id>
flutter build apk --debug --target-platform android-arm64
python3 tool/verify_apk.py build/app/outputs/flutter-apk/app-debug.apk
```

`tool/feed_smoke.dart`는 실제 GitHub SDK Atom 피드를 읽는 네트워크 확인용입니다. 단위·위젯 테스트는 실제 Gemini API 키 없이 실행됩니다. 실제 Gemini 응답, Keystore, 클립보드, 브라우저 복귀, 권한 거절·허용, 재부팅 후 알림은 Android 기기에서 별도 확인해야 합니다.

## 릴리스 서명 및 배포

업데이트 APK는 **항상 같은 서명 키**를 사용해야 합니다. 서명 키와 비밀번호를 Git이나 릴리스에 올리지 마세요. 클라우드에서 생성한 개인 서명 자료는 `/workspace/toolchains/signing/`에 보관하며, 보안 저장소에 별도 백업해야 합니다. 해당 디렉터리와 `android/key.properties`는 공개 저장소에 포함하지 않습니다.

다른 환경에서는 `android/key.properties`를 다음 형식으로 직접 준비하세요. 실제 값은 로컬에만 넣습니다.

```properties
storeFile=/absolute/private/path/release.p12
storePassword=<private-password>
keyAlias=ai-briefing
keyPassword=<private-password>
```

```bash
bash tool/build_release.sh
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --verbose build/release/ai-morning-briefing-arm64.apk
```

결과물은 `build/release/ai-morning-briefing-arm64.apk`, `build/release/SHA256SUMS.txt`입니다. 서명 설정이 없는 release 빌드는 debug 키로 대체하지 않습니다. APK 서명을 검증한 뒤 머지된 main 커밋을 대상으로 태그·GitHub Release를 생성합니다. CI는 분석, 테스트, arm64 debug 빌드를 실행하며, 개인 서명 키를 보유하거나 공개하지 않습니다.

## 데이터와 보안

API 키는 Android Keystore 기반 `flutter_secure_storage`에 암호화 저장하고 요청 헤더로 Google에 전송합니다. 로그·코드·URL 쿼리에 API 키를 넣지 않습니다. Android 백업을 비활성화해 키와 기기 암호화 자료의 잘못된 복원을 방지합니다. 요약 캐시는 최대 500개, 읽은 기사 식별자는 최대 2,000개입니다. 앱 삭제 시 기기의 저장 데이터도 삭제됩니다. API 키를 폐기하려면 Google AI Studio에서도 삭제하세요.

AI 요약은 부정확할 수 있습니다. Google 무료 서비스의 입력 데이터 이용 조건은 [Gemini 이용약관](https://ai.google.dev/gemini-api/terms)을 확인하세요. 민감한 개인 정보를 포함하는 피드는 등록하지 마세요. 알림 문구는 예약 시 무작위로 선택되며 반복 알림에 사용됩니다. 시간대 변경 후에는 앱을 다시 열어 알림을 재예약하세요.

기본 소스에는 기업 공식 피드, 개인 블로그, 매체, 커뮤니티 피드가 함께 포함됩니다. RSSHub는 제3자 서비스이며 Daily Papers 수집 실패 시 arXiv `cs.AI`로 대체합니다. 피드의 무차단·무제한 접근을 보장하지 않습니다. 설정에서 끄거나 대체 피드를 추가할 수 있습니다.

정확한 알림에는 사용자가 허용하는 `SCHEDULE_EXACT_ALARM`을 사용합니다. 알람 시계·달력 앱을 위한 자동 허용 권한인 `USE_EXACT_ALARM`은 사용하지 않습니다.
