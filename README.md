# ios-release-kit

Diagnose what is blocking your App Store submission via the App Store Connect API, then fix it from the command line. Built from a real launch in Sept 2026. Korean docs below.

## 30초 요약

**무엇**: App Store Connect API로 지금 제출을 막는 원인을 진단하고(`fastlane doctor`), 커맨드 한 줄로 고친다.

**왜**: 2026년 9월 실제 출시에서 이런 것들이 제출을 막았다.
- IAP가 심사에 안 들어감(심사 스크린샷 없음)
- 연령등급 선언이 비어 있어 제출 버튼이 안 눌림
- 빌드를 버전에 안 붙여 제출 초안에 앱 버전이 빠짐
- deliver가 비UTF-8 로케일에서 메타데이터 업로드 중 죽음
- 심사 연락처 전화번호 형식(E.164) 오류
- 앱 이름이 이미 선점돼 있어 앱 생성 단계에서야 발견됨
- 빌드마다 수출 규정(암호화) 질문이 뜸(`ITSAppUsesNonExemptEncryption` 없음)
- 제출한 뒤 며칠째 상태가 그대로인데, 큐에 들어가 있기는 한 건지 알 수 없음

**누구**: Claude Code나 Cursor로 앱은 다 만들었는데 출시 단계에서 막힌 사람.

## 설치

```bash
brew install fastlane
cp -r ios-release-kit/fastlane <내앱>/fastlane   # 기존 fastlane 있으면 lib/ 와 레인만 합친다
cp fastlane/.env.template fastlane/.env          # 채우기
# ASC 웹 › 사용자 및 액세스 › 통합 › 키 생성(App Manager) → .p8을 fastlane/keys/ 에 저장
```

Ruby 3 이상이 필요하다(`brew install ruby`). macOS 기본 Ruby 2.6은 이 kit을 못 읽는다.

## 진단

```bash
LC_ALL=en_US.UTF-8 fastlane doctor
```

예시 출력:
```
✅ 앱      MyApp · com.example.app (id 1234567890)
✅ 버전    1.0 · PREPARE_FOR_SUBMISSION
❌ IAP     com.example.app.pro MISSING_METADATA: 심사 스크린샷 없음 → fastlane iap_screenshot iap_id:abc123 path:<png>
❌ 연령등급 선언 항목 3개 비어 있음 → fastlane age_rating
✅ 심사진행 애플 큐에서 대기 3일째 · 제출 2026-09-11 18:32 (WAITING_FOR_REVIEW)
– 제출초안 제출 초안 없음
– 유료계약 API로 못 읽음. 유료 IAP면 ASC 웹 › 비즈니스 › 유료 앱 계약 활성 확인
❌ 2개 · 제출 가능: 아니오
```

## 고치기

| 항목 | 명령 | 하는 일 |
|---|---|---|
| 빌드 첨부 | `fastlane attach_build build:<빌드번호>` | 최신 VALID 빌드를 편집 중인 버전에 붙인다(옵션 없으면 최신) |
| 연령등급 | `fastlane age_rating override:'key=value,key=value'` | 선언을 NONE/false로 채우고, 필요한 항목만 override로 덮어쓴다 |
| IAP 스크린샷 | `fastlane iap_screenshot iap_id:<id> path:<png>` | 심사용 스크린샷을 업로드한다(`product_id:<productId>`로도 지정 가능) |
| 메타데이터 | `fastlane release_metadata` | `fastlane/metadata/<locale>/`를 ASC에 업로드한다(제출은 안 함) |
| 스크린샷 업로드 | `fastlane upload_screenshots` | `fastlane/screenshots/<locale>/<device>/*.png`를 ASC에 올린다 |

쓰기 레인 앞에 `DRY_RUN=1`을 붙이면 실제로 보내는 대신 요청 내용만 출력한다.

## 배포

```bash
fastlane verify_auth        # 인증 확인
fastlane beta                # 빌드 + TestFlight 업로드
fastlane release_metadata    # 메타데이터 업로드
# 이후 ASC 웹에서 수동 Submit, 또는 v1.1+부터 fastlane release
```

`fastlane/metadata.example/`을 복사해 채운 뒤 실행한다: `cp -r fastlane/metadata.example fastlane/metadata`.

## 스크린샷

```bash
scripts/screenshots.sh booted fastlane/screenshots/ko/iPhone 01-home
```

시뮬레이터 상태바를 정리하고 캡처한 뒤 1320×2868(6.9인치)로 맞춘다.

UI로 찍지 않고 CLI로 찍는 이유가 있다. 시뮬레이터 창 위로 마우스를 옮기는 것만으로 홈 인디케이터나 시계 UI가 살아나서 스크린샷에 섞여 들어간다. `simctl`로 캡처하면 포인터가 기기 화면 근처에 갈 일이 없고, 상태바도 `simctl status_bar override`로 고정되며, 해상도도 ASC가 원하는 네이티브로 나온다.

## Claude Code와 쓰기

`claude/` 폴더에 프로젝트용 `CLAUDE.md.template`, 심사 전 점검 스킬(`skills/app-store-review/`), 매일 상태를 확인하는 스케줄 프롬프트(`scheduled/review-daily.md`)가 들어 있다. 필요한 것만 골라 프로젝트에 복사해 쓴다.

## 함정 목록

실제로 막혔던 것들의 원인·확인·해결은 [`docs/review-checklist.md`](docs/review-checklist.md)에 정리했다.

## 한계

- 유료 앱 계약 활성 여부는 API로 못 읽는다(ASC 웹에서 확인).
- 제출 초안에 앱 버전을 추가하는 API 호출이 실제 출시 중 HTTP 500을 냈다. `doctor`는 경고만 하고 웹에서 처리하도록 안내한다.
- 이 kit은 2026년 9월 실제 출시 한 건으로 검증됐다. 여러 앱·커뮤니티 검증은 아직이다.

## 라이선스

MIT
