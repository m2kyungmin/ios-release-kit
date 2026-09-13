---
name: app-store-review
description: App Store 제출 전 점검 — fastlane doctor 실행 + 정적 검사 + 함정 체크리스트 대조
---
1. `LC_ALL=en_US.UTF-8 fastlane doctor` 를 실행하고 출력을 그대로 보여 준다.
2. ❌ 항목마다 화살표 뒤 명령을 제안한다. 쓰기 레인(attach_build, age_rating, iap_screenshot)은 먼저 `DRY_RUN=1`로 요청 본문을 보여 주고 사람 승인 뒤 실행한다.
3. 정적 검사: Info.plist에 `ITSAppUsesNonExemptEncryption`, `NSCameraUsageDescription` 등 사용하는 권한의 설명 문구, `PrivacyInfo.xcprivacy` 존재.
4. `docs/review-checklist.md` 표의 증상과 대조해 해당되는 줄을 인용한다.
5. 결과를 «제출 가능: 예/아니오 + 남은 일 목록»으로 끝낸다.
