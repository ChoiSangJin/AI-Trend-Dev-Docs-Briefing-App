## AI 모닝 브리핑 v1.0.8

- 공개 API 6종을 연결합니다. GitHub 릴리스 5개와 arXiv는 기존 토글을 보존해 API로 전환하고 Atom/RSS를 대체 주소로 유지합니다.
- Hacker News 공식 API 최신 기술 담론, DEV AI 태그 인기글, Hugging Face 모델 정보(다운로드순), AI Stack Exchange 질문 메타데이터를 추가해 기본 27개를 제공합니다. 추가 API 키는 필요하지 않습니다.
- API 결과는 실행 중 15분 캐시합니다. HN은 목록 1회와 최대 10개 항목(동시 5개)으로 제한하고 GitHub 한도 reset·Stack Exchange backoff/할당량·HTTP 429를 처리합니다. API 캐시·대기 정보는 재시작 후 유지하지 않습니다.
- 전체 브리핑·요약 최대 10개 제한과 기존 설정·사용자 피드를 유지합니다. 모든 출처가 매번 표시되지는 않습니다. 모델 정보와 질문은 새 릴리스·검증된 답변이 아니며, 추천·다운로드 수는 기사 조회수가 아닙니다.

검증: 분석·테스트 100개, 실제 수집 코드로 GitHub·arXiv·Hugging Face API 확인, arm64 release APK·기존 서명 일치·체크섬·16KB ZIP 정렬.

제한: HN·DEV·Stack Exchange 실연결은 개발환경의 새 도메인 제한으로 미확인입니다. HN 공식 스키마와 DEV Forem 명세를 확인하고 응답별 테스트를 수행했습니다. 필요한 도메인은 환경 설정 초안에 저장했습니다. 기존 LlamaIndex Blog·LangChain Blog 등의 RSS 문제는 별도 미해결입니다.

버전 1.0.8+9, Android 7.0 이상 arm64용입니다.

Source: 8e4ba77f8c3a2c77ec0451001ffe6d0c29e3f204
