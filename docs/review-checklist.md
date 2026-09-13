# App Store 심사·제출 함정 체크리스트

| # | 증상 | 원인 | 확인 | 해결 |
|---|---|---|---|---|
| 1 | IAP가 심사에 안 들어감 | 심사 스크린샷 없음(`MISSING_METADATA`) | `fastlane doctor`의 IAP 줄 | `fastlane iap_screenshot iap_id:<id> path:<png>` |
| 2 | 제출 버튼이 안 눌림 | 연령등급 선언이 비어 있음 | `fastlane doctor`의 연령등급 줄 | `fastlane age_rating` |
| 3 | 제출 초안에 앱 버전이 없음(IAP만 있음) | 버전에 빌드가 안 붙었거나, 초안에 항목을 안 넣음 | `fastlane doctor`의 빌드·제출초안 줄 | `fastlane attach_build` 실행 후 ASC 웹 › 심사 제출 › 항목 추가 |
| 4 | `deliver`가 메타데이터 업로드 중 죽음 | 셸 로케일이 UTF-8이 아님 | 실행 전 `echo $LC_ALL` | 항상 `LC_ALL=en_US.UTF-8 fastlane release_metadata`로 실행 |
| 5 | 심사 연락처 오류 | 전화번호가 E.164 형식이 아님 | `fastlane doctor`의 심사정보 줄(`+`로 시작하는지) | `fastlane/metadata/review_information/phone_number.txt`를 E.164로 수정(예 `+821012345678`) |
| 6 | 앱 이름 "이미 사용 중" | 이름이 이미 선점됨 | `fastlane create_app` 실행 후 안내에 따라 ASC 웹에서 앱 생성 시도 | 이름을 바꿔 ASC 웹에서 앱 생성 재시도 |
| 7 | 빌드마다 "수출 규정" 질문이 뜸 | Info.plist에 `ITSAppUsesNonExemptEncryption` 없음 | `INFO_PLIST` 설정 후 `fastlane doctor`의 암호화 줄 | Info.plist에 `ITSAppUsesNonExemptEncryption`을 `false`로 추가 |
| 8 | 실기기에 IAP 상품이 안 뜸 | ASC 전파 지연이거나 유료 앱 계약 미체결 | ASC 웹 › 비즈니스 › 유료 앱 계약 상태 | 몇 시간 기다리거나 계약을 먼저 체결 |
| 9 | 복원 버튼이 계속 "잠시만요"에 머무름 | `AppStore.sync()` 응답이 안 옴(무한 대기) | 복원 버튼을 눌러 응답 시간 확인 | 20초 시한을 두고 시한 초과 시 실패로 처리 |
| 10 | 개인정보처리방침 URL이 없음 | 등록 안 함 | `fastlane doctor`의 개인정보 줄 | GitHub Pages 한 장으로 충분 — 페이지 만들어 URL 등록 |
| 11 | 제출은 했는데 며칠째 상태가 그대로 — 정상인지 알 수 없음 | ⑴ 실제로는 큐에 안 들어가 있거나(제출 초안만 있음·미해결 항목) ⑵ 큐에서 대기 중 | `fastlane doctor`의 심사진행 줄 | 큐에 없으면 위 항목들 해결 후 ASC 웹 › 심사 제출. 큐에 있으면 경과일을 보고, 7일 넘으면 ASC 웹 › 문의하기 › App Review로 상태 문의 |
| 12 | 설정은 맞는데 `Product.products(for:)`가 빈 배열을 돌려줌 | ⑴ 앱이 요청하는 productId가 ASC에 없음(오타·미생성) ⑵ 유료 앱 계약 미체결 ⑶ ASC 변경 직후 전파 지연 | `fastlane doctor`의 상품ID 줄(.storekit ↔ ASC 대조) | ⑴이면 id를 맞춘다. ⑵는 ASC 웹 › 비즈니스에서 확인(API로 못 읽음). ⑶이면 기다린다 |

출처를 구분해 둔다.

- **1~10**: 2026-09 실제 출시에서 우리가 직접 막힌 것. 추측 항목 없음.
- **11~12**: 커뮤니티 순회에서 반복 확인된 것(2026-09-13 기준 — 11번은 애플 개발자 포럼 11건·Reddit 2건, 12번은 포럼 4건·Threads 1건). 12번의 ⑵⑶은 우리 출시에서 직접 겪은 것과 같은 원인이고(8번 참조), ⑴은 `doctor`가 새로 판정한다.

진단이 못 하는 것도 적어 둔다. ASC가 돌려주는 상품 `state` 값은 그대로 출력만 하고 의미를 해석하지 않는다. 공식 문서에 enum 전체가 공개돼 있지 않아 확인할 수 없기 때문이다.
