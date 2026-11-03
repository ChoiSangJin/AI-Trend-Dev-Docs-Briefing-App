## AI 모닝 브리핑 v1.0.9

- 실패가 확인된 기본 LlamaIndex Blog·LangChain Blog RSS 주소를 제외합니다. 두 프로젝트의 공식 릴리스 API는 유지합니다. 블로그 본문 수집이 복구된 것은 아닙니다.
- 실제 연결을 검증한 Google Gen AI SDK·Ollama·vLLM·Hugging Face Transformers 공식 GitHub 릴리스 API를 추가해 기본 소스를 29개로 정리합니다. draft/prerelease 표시와 rc·alpha·beta·preview·dev 태그를 제외하고, 무료 API 한도·Atom 대체를 유지합니다.
- VentureBeat의 성공한 RSS 결과를 실행 중 5분간 재사용해 반복 요청을 줄입니다. 사이트의 429 제한 자체를 해제하지는 않습니다.
- HN 최신 항목은 플랫폼 등록 시각이 없거나 30일보다 오래되거나 하루 이상 미래인 경우 제외합니다. AI에 플랫폼 등록 시각을 보내고 원문 최초 발행일로 추측하지 않도록 지시합니다. 기존 HN 요약만 한 번 다시 생성하며 다른 요약·읽기 기록은 보존합니다. AI 사실 정확성을 보장하는 검증기는 아닙니다.
- 사용자 추가 피드·별도 수정 URL·다른 소스 토글·전체 브리핑 최대 10개 제한을 유지합니다.

검증: 분석·테스트 105개, 실제 수집 코드로 새 4개를 포함한 공식 API 7곳의 결과 확인, arm64 release APK·동일한 서명·체크섬·16KB ZIP 정렬.

버전 1.0.9+10, Android 7.0 이상 arm64용입니다.

Source: 8e9cb39ae558da71d62a6fe4c53b55b1b9e56530
