# AI 모닝 브리핑

해외 AI 소식과 개발 문서를 한국어 세 줄로 읽는 Android 앱입니다. 별도 백엔드, 외부 DB, 로그인, 광고가 없습니다. 사용자가 자신의 Google Gemini API 키를 등록하며, 모든 설정·학습 기록·요약 캐시는 기기에 저장합니다.

## 사용하기

GitHub Releases에서 **arm64 APK**를 내려받아 Android 7.0(API 24) 이상 arm64 기기에 설치하세요. 최초 실행 시 3단계 안내에 따라 Google AI Studio에서 발급한 API 키를 등록합니다. 지역·계정별 사용 가능 여부와 무료 제공량은 Google 정책에 따라 달라지며, 영구 무료를 보장하지 않습니다.

- 각 출처의 최신 소식을 하나씩 먼저 고른 뒤 최대 10개를 모아, 저장된 요약을 먼저 보여줍니다.
- API 키의 접두사나 길이는 제한하지 않습니다. 앞뒤 공백을 제거하고 빈 입력만 안내하며, Google 모델 목록 조회의 성공 여부로 키와 사용 가능한 텍스트 Flash 모델을 확인한 후 저장합니다.
- 새로운 소식은 Google 모델 목록에서 확인한 텍스트 Flash 모델에 한 번으로 묶어 요청합니다. 목록에 있는 Gemini 3 이상 안정 버전 Flash-Lite 중 최신 버전을 우선하고, 이어 안정 버전 Flash와 최신 별칭을 선택합니다. 새 프로젝트 접근이 제한된 2.5 계열은 자동 선택하지 않습니다. 기존 2.5 모델 설정도 업데이트 후 첫 요약에서 저장된 키로 모델 목록을 다시 확인해 갱신합니다. 제목, 발췌문, 출처, 기사 식별자가 Google로 전송됩니다. 기사마다 제목 180자·발췌문 1,200자까지 보내고 간결한 출력을 요청합니다. 전문을 수집하거나 추측하지 않습니다.
- 키 확인은 콘텐츠를 생성하지 않는 모델 목록 조회로 분리합니다. 요약 생성만 65초 간격 제한을 적용하므로 키 확인 직후 첫 요약을 요청할 수 있습니다. 계정별 무료 한도는 더 낮을 수 있으며 429 응답을 받으면 추가 대기합니다.
- 키 확인 성공이 요약 생성의 지역·권한·할당량을 보장하지는 않습니다. Google 오류는 HTTP 코드와 안전한 상태 코드로 구분해 안내하며 원문 오류 본문이나 키는 표시하지 않습니다.
- 요약 요청은 응답 본문까지 최대 120초를 기다리고, 시간 초과 시 실제 요청을 취소합니다. 생성 요청이 404일 때 실패한 모델을 기기에 기록해 제외하고 목록을 갱신한 후 다른 모델로 한 번 전환합니다. 같은 모델을 다시 선택하거나 무한 재시도하지 않습니다. 400·401·403·429·503 외 5xx·시간 초과는 자동 재시도하지 않으며 원인 미확정의 시간 초과를 키 오류로 표시하지 않습니다. 키를 직접 다시 연결하면 이전 프로젝트에서 기록한 실패 모델을 초기화합니다.
- 요약이 없거나 실패하면 원문 제목·발췌문을 보여줍니다. 피드에 없는 정보를 완전한 기사 요약으로 표시하지 않습니다.
- 설정에서 소스를 끄거나 공개 HTTPS RSS/Atom 피드를 추가할 수 있습니다. 변경 후 브리핑을 새로고침하세요. 게시 빈도가 높은 피드가 다른 출처를 밀어내지 않도록 출처별로 번갈아 기사를 선택합니다. RSS의 숫자 시간대(`+0900`, `+0000`)도 날짜 정렬에 반영합니다.
- 연속 학습은 기기 현지 날짜 기준 하루 한 번만 증가합니다.
- 알림은 설정에서 직접 켭니다. Android 13+ 알림 권한과 Android 12+ 정확한 알림 권한을 요청하며, 정확한 알림 권한이 없으면 대략적인 시간에 알립니다. 기본 시간은 오전 8시입니다. 기기 절전 정책에 따라 지연될 수 있습니다.

Google의 [모델 수명 주기 안내](https://ai.google.dev/gemini-api/docs/deprecations#gemini-2.5-flash-models)는 2.5 계열의 신규 사용 접근 제한과 최신 모델 사용 권장을 설명합니다. 모델 목록에 표시되는 것만으로 해당 프로젝트의 실제 생성 접근을 보장하지 않습니다.

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

`tool/feed_smoke.dart`는 실제 GitHub SDK 릴리스를 API 또는 Atom 대체 피드로 읽는 네트워크 확인용입니다. 단위·위젯 테스트는 실제 Gemini API 키 없이 실행됩니다. 실제 Gemini 응답, Keystore, 클립보드, 브라우저 복귀, 권한 거절·허용, 재부팅 후 알림은 Android 기기에서 별도 확인해야 합니다.

## 릴리스 서명 및 배포

기존 앱 위에 업데이트하려면 **같은 서명 키**를 사용해야 합니다. v1.0.12는 사용자 승인에 따라 GitHub Secrets의 새 키로 전환하므로 기존 앱을 삭제한 뒤 새로 설치해야 합니다. 삭제 시 저장된 API 키·설정·읽음 기록이 사라집니다. 서명 키와 비밀번호를 Git이나 릴리스에 올리지 마세요. 클라우드에서 생성한 개인 서명 자료는 `/workspace/toolchains/signing/`에 보관하며, 보안 저장소에 별도 백업해야 합니다. 해당 디렉터리와 `android/key.properties`는 공개 저장소에 포함하지 않습니다.

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

기본 소스에는 기업 공식 피드, 개인 블로그, 매체, 커뮤니티 피드가 함께 포함됩니다. 논문 소스는 arXiv `cs.AI`를 직접 조회합니다. 공용 RSSHub의 접근 제한을 확인해 이전 RSSHub 주소 설정도 arXiv로 갱신합니다. 빈 정상 피드는 새 항목이 없는 것으로 처리합니다. 피드의 무차단·무제한 접근을 보장하지 않습니다. 설정에서 끄거나 대체 피드를 추가할 수 있습니다.

정확한 알림에는 사용자가 허용하는 `SCHEDULE_EXACT_ALARM`을 사용합니다. 알람 시계·달력 앱을 위한 자동 허용 권한인 `USE_EXACT_ALARM`은 사용하지 않습니다.

## 추가 소스 (v1.0.5)

기존 10개에 HNRSS AI(50점 이상), Lobsters AI, The Decoder, VentureBeat AI, MIT Technology Review 전체 피드, LangChain·LlamaIndex 블로그 및 GitHub 릴리스, Google DeepMind, Microsoft AI, Interconnects, Ahead of AI를 추가해 기본 23개를 제공합니다. MIT 피드는 AI 전용이 아닙니다. HNRSS 점수 조건은 주간·월간 조회수 순위가 아닙니다.

기존 소스의 켜기/끄기와 사용자 피드를 보존하면서 새 기본 소스를 추가합니다. 수집에 실패한 출처는 다른 소스 수집을 막지 않고 경고를 표시합니다. 전체 브리핑과 AI 요약 한도는 여전히 최대 10개이며, 10개보다 많은 출처가 켜져 있으면 최신 기사가 있는 출처를 우선하므로 모든 출처가 매번 표시되지는 않습니다.

GitHub Trending은 공식 REST Trending 엔드포인트가 없고, The Neuron은 확정된 RSS 주소가 없어 포함하지 않았습니다. Reddit·X 직접 수집도 추가하지 않았습니다. 새 외부 RSS 주소는 클라우드 도메인 접근 제한 때문에 실제 응답을 확인하지 못했으며, 주소 변경·차단·구독 제한에 따라 실패할 수 있습니다. LangChain·LlamaIndex GitHub 릴리스 피드는 실제 XML 응답으로 검증합니다.

## 피드 실패 진단 수정 (v1.0.6)

RSSHub 공용 서버의 403 접근 제한과, arXiv가 정상 XML이지만 항목 0개를 반환하는 상황을 실제 확인했습니다. arXiv 직접 조회 및 기존 주소 설정 갱신, 빈 RSS 성공 처리, 2MB 용량 제한·다른 문서 응답 구분을 수정했습니다. VentureBeat 429, LlamaIndex 404, Ahead of AI·LangChain 형식 오류는 사용자 화면에서 확인했으나 개발환경의 도메인 제한으로 원문 응답을 검증하지 못했습니다. 새 주소를 추측해서 교체하지 않았으며 해당 소스들은 해결된 것으로 간주하지 않습니다.

## 대용량 뉴스레터 및 429 대기 처리 (v1.0.7)

사용자 화면에서 Ahead of AI가 2MB 제한을 초과하는 것을 확인해 이 기본 소스만 최대 8MB를 허용합니다. 다른 소스와 사용자 피드는 기존 2MB 제한을 유지하고, 기사 발췌문은 계속 3,500자로 제한합니다. 실제 Ahead of AI 응답은 도메인 정책으로 검증하지 못했으므로 전체 크기와 수집 성공 여부는 미확인입니다.

HTTP 429 응답의 Retry-After(초 또는 HTTP 날짜)를 반영합니다. 없거나 해석할 수 없으면 5분을 기다리고, 대기는 1분~24시간으로 제한합니다. 실행 중인 FeedService에서 같은 URL의 수동 새로고침 요청을 대기 시간 동안 억제합니다. 앱 재시작 후 대기 정보는 유지하지 않습니다. 자동 재시도는 하지 않습니다. LlamaIndex 주소와 LangChain 원문은 아직 검증하지 못했습니다.

## 공개 API 소스 (v1.0.8)

기본 소스는 27개입니다. Hacker News 공식 Firebase API(최신 기술 담론), DEV AI 태그 인기글, Hugging Face 공개 텍스트 생성 모델 메타데이터(다운로드순), AI Stack Exchange 질문 메타데이터를 추가합니다. 모델 메타데이터는 새 릴리스·성능 검증이 아니며, 질문 목록도 검증된 답변이 아닙니다. HNRSS AI 소스와 기존 블로그 RSS 설정은 유지합니다.

OpenAI Python SDK·Anthropic Python SDK·Claude Code·LangChain·LlamaIndex 릴리스는 GitHub REST API로 전환하고 기존 Atom을 대체 피드로 유지합니다. arXiv는 검색 API(Atom)로 전환하며 RSS를 대체 주소로 유지합니다. 기존 토글과 사용자 피드는 보존하고 이전 주소·형식은 자동 갱신합니다. 추가 API 키는 필요하지 않으며, 공개 무료 한도는 서비스 정책에 따릅니다. GitHub 비인증 한도 초과는 서버 reset 지침 동안 API 요청을 쉬고 Atom으로 대체합니다.

API 결과는 현재 앱 실행 중 15분간 재사용합니다. Hacker News는 ID 목록 1회와 최대 10개 항목 조회(동시 5개)로 제한하고, Stack Exchange backoff·quota_remaining을 준수합니다. 기존 HTTP 429 대기 처리도 유지합니다. 브리핑·AI 요약은 전체 최대 10개이며 모든 소스가 매번 화면에 나타나는 것은 아닙니다. API 캐시·대기 정보는 재시작 후 유지하지 않습니다.

실연결 확인: GitHub 릴리스·arXiv 검색·Hugging Face 모델 API를 `dart run tool/public_api_smoke.dart`로 확인했습니다. HN 공식 스키마와 DEV Forem 공개 명세도 확인했습니다. HN·DEV·Stack Exchange 실제 응답은 개발환경의 새 도메인 접근 제한으로 확인하지 못했습니다. 이를 성공한 실연결로 간주하지 않습니다. 필요한 도메인은 환경 설정 초안에 저장했습니다. 기존 LlamaIndex Blog·LangChain Blog 등의 RSS 실패는 별도 문제로 남아 있습니다.

## 검증된 공식 소스 정리 (v1.0.9)

기본 목록은 29개입니다. 무료 공개 GitHub 릴리스 API로 Google Gen AI SDK, Ollama, vLLM, Hugging Face Transformers를 추가했으며 실제 수집 코드로 네 곳 모두의 항목을 확인했습니다. GitHub의 draft/prerelease 표시 외에 rc·alpha·beta·preview·dev 태그도 제외합니다. 호출 한도와 Atom 대체 처리는 유지합니다.

실패가 확인된 기본 LlamaIndex Blog·LangChain Blog RSS 주소는 목록과 기존 저장 설정에서 제외합니다. 두 프로젝트의 공식 릴리스 API는 계속 제공합니다. 블로그 본문 수집이 복구된 것은 아닙니다. 사용자 추가 피드와 별도로 변경한 URL, 다른 소스의 토글은 보존합니다.

VentureBeat는 정상 XML 응답을 확인했으며 성공한 결과를 앱 실행 중 5분간 재사용해 과도한 재요청을 줄입니다. 서버의 429 제한 자체를 해제하는 것은 아닙니다. 다른 RSS의 수동 갱신 방식과 API 15분 캐시는 유지합니다.

HN 최신 항목은 플랫폼 등록 시각이 없거나 30일보다 오래됐거나 하루 이상 미래인 경우 제외합니다. AI 입력에는 플랫폼 등록 시각을 보내고 원문 최초 발행일로 추측하지 않도록 지시합니다. 이 정보가 없던 기존 HN 요약만 한 번 무효화해 다시 생성하며 다른 요약과 읽기 기록은 유지합니다. AI 결과의 사실 정확성을 보장하는 검증기는 아닙니다.

## Gemini 503 복구 (v1.0.10)

503에서는 HTTP Retry-After의 초·HTTP 날짜를 읽고, 없거나 잘못된 경우 5초를 기다립니다(최소 1초, 최대 24시간). 대기가 30초 이하일 때만 Google 모델 목록을 갱신해 현재 요청에서 시도하지 않은 다른 모델로 한 번 전환합니다. 30초를 넘으면 자동 대기·생성을 하지 않고, 지정된 대기 시각을 저장해 재시작 후 수동 요청에도 적용합니다. 404와 섞여도 한 작업의 생성 요청은 최대 두 번입니다. 다른 모델이 없으면 같은 모델로 재요청하지 않습니다.

503 모델은 영구 제외하지 않으며, 성공한 대체 모델 설정은 재사용합니다. 400·401·403·429·500·시간 초과는 자동 전환하지 않습니다. 5xx 오류에는 실제 요청 모델을 표시하고, 원문 오류 본문과 키 값은 표시하지 않습니다. Google 전체 장애나 모든 모델의 이용 불가 상태를 해결하는 기능은 아닙니다.

## 본문 중심 브리핑 (v1.0.11)

- HN 링크 기사는 댓글 페이지 대신 실제 발행처로 연결하며 기존 읽음 식별자는 유지합니다.
- 실제 본문/발췌문이 80자 이상인 항목을 요약합니다. 제목·추천수·모델 목록 등의 메타데이터와 HNRSS 링크 설명은 AI 요약에서 제외하고 안내를 표시합니다. 외부 기사 전문을 추가 수집하지 않습니다.
- 본문이 있는 항목을 출처별로 순환 선택해 최대 10개를 채운 뒤 정보만 제공되는 항목으로 보충합니다. 일부 종합 피드는 기술 키워드로 관련성을 선별하며 사용자 지정 피드는 이 필터를 적용하지 않습니다.
- 이전 정책의 요약 캐시는 한 번 재생성합니다. API 키, 설정, 읽음 기록은 유지합니다.

## 공식 AI 제공사 소스

| 제공사 | 수집 소스 |
| --- | --- |
| Google | Google AI Blog, Google DeepMind RSS, Google Developers Blog RSS, Google Gen AI SDK 릴리스 |
| OpenAI / GPT | OpenAI News RSS, Python SDK 릴리스 |
| Anthropic / Claude | Python SDK 및 Claude Code 공식 릴리스 |
| xAI / Grok | xAI Python SDK 공식 GitHub Releases API, Atom 대체 피드 |

SDK 릴리스는 개발 도구 변경 소식이며 제공사의 전체 블로그·제품 발표를 대체하지 않습니다. X(트위터) 게시물 피드와 xAI(Grok)는 구분합니다. 사용자 피드는 기본 소스 수와 별도로 최대 30개까지 추가할 수 있습니다.

### 공식 블로그 RSS 확인 (2026-11-11)

Google Developers Blog의 `https://developers.googleblog.com/feeds/posts/default/`는 HTTP 200 및 RSS 20개 항목을 확인해 추가했습니다. 기존 설치에는 소스 목록 병합으로 추가되며 기존 중지 설정과 사용자 피드는 유지됩니다.

Anthropic News, xAI News, X Blog 홈페이지는 접속되지만 페이지에 RSS/Atom 자동 검색 링크를 찾지 못했습니다. 확인한 `/rss.xml`, `/feed.xml`, 뉴스 RSS 후보와 X 블로그 RSS 후보는 404여서 기본 소스로 등록하지 않았습니다. 공식 RSS가 절대 없다는 의미는 아닙니다. Anthropic·Claude와 xAI는 검증된 공식 GitHub 릴리스 수집을 유지하며 X 게시물이나 타사 생성 RSS는 추가하지 않습니다.

`dart run tool/feed_smoke.dart`는 Google Developers·DeepMind·OpenAI RSS와 OpenAI·Anthropic·Claude Code·xAI 공식 릴리스를 출처별로 개별 수집해 일부 출처 실패가 다른 출처 성공에 가려지지 않도록 확인합니다.

### GitHub Actions로 서명된 릴리스 게시

현재 배포는 main의 `Publish signed Android release` 워크플로를 수동 실행합니다. 저장된 GitHub Secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`만 사용하며 값을 출력하지 않습니다. 임시 서명 파일은 작업 종료 시 삭제합니다.

`pubspec.yaml`과 설정 화면 버전, `RELEASE_NOTES.md`를 갱신해 머지한 뒤 실행하세요. 워크플로는 테스트·분석·릴리스 빌드 후 기존 공개 APK와 서명 인증서·앱 ID 일치, 버전 코드 증가, arm64 구성, 체크섬·정렬을 검증합니다. 성공한 APK와 체크섬만 GitHub Releases에 게시하며 기존 태그가 있으면 중단합니다. 로컬에 보관된 서명 파일은 Actions 배포에서 사용하지 않습니다.

서명 키 전환은 `allow_signing_change` 입력을 명시적으로 true로 실행한 경우에만 허용합니다. 기본값은 false로, 이후 릴리스에서는 새로 배포된 APK의 인증서와 일치를 계속 확인합니다. 키 전환 시 릴리스 안내에 삭제·재설치 및 데이터 삭제 안내를 자동으로 추가합니다. APK 자체는 항상 현재 GitHub Secrets 인증서와 일치해야 합니다.

## IT·개발 소식 화면

하단의 `IT·개발` 화면은 기술 블로그 RSS를 기존 AI 브리핑과 분리하여 출처별로 최대 10개 보여줍니다. 원문 링크, 읽음 기록, 소스별 켜기/끄기, 새로고침을 지원합니다. 이 화면은 피드에서 제공하는 발췌문을 표시하며 Gemini 요약 요청을 추가하지 않습니다. AI 브리핑의 10개 제한과 독립적으로 선택합니다.

수집 확인: `dart run tool/it_feed_smoke.dart`. 개발 환경의 도메인 허용이 적용되면 실제 피드 응답과 형식을 출처별로 검사합니다.
