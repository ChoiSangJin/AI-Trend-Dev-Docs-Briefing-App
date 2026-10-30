## AI 모닝 브리핑 v1.0.6

- 공용 RSSHub의 운영용 접근 제한(403)을 확인해 논문 소스를 arXiv cs.AI 직접 조회로 변경합니다. 기존에 저장한 RSSHub 주소도 토글을 보존해 갱신합니다.
- 정상 RSS/Atom에 항목이 없는 경우를 수집 실패로 오판하지 않습니다.
- 2MB 용량 초과와 RSS/Atom이 아닌 문서 응답을 구분해 안내합니다.

남은 문제: VentureBeat의 429, LlamaIndex Blog의 404, Ahead of AI·LangChain의 파싱 실패는 이 버전에서 해결된 것으로 표시하지 않습니다. 해당 사이트 원문은 개발환경 접근 정책으로 검증하지 못했습니다. 수집 가능한 소스의 브리핑은 계속 제공됩니다.

검증: 분석·테스트 82개, arm64 release APK, 기존 버전과 같은 서명, 체크섬·16KB ZIP 정렬. 버전 1.0.6+7이며 Android 7.0 이상 arm64용입니다.

Source: aef67e68267299d54a728e13309e8ac660e59b9a
