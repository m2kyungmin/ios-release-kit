# 순수 진단 함수. 네트워크 없음. 입력은 ASC 응답을 JSON.parse한 해시.
module AscDoctor
  Result = Struct.new(:id, :label, :status, :message, :fix)

  AGE_KEYS = %w[
    alcoholTobaccoOrDrugUseOrReferences contests gamblingSimulated horrorOrFearThemes
    matureOrSuggestiveThemes medicalOrTreatmentInformation profanityOrCrudeHumor
    sexualContentGraphicAndNudity sexualContentOrNudity violenceCartoonOrFantasy
    violenceRealistic violenceRealisticProlongedGraphicOrSadistic gunsOrOtherWeapons
    gambling unrestrictedWebAccess seventeenPlus lootBox advertising ageAssurance
    parentalControls healthOrWellnessTopics messagingAndChat userGeneratedContent
  ].freeze

  ICON = { ok: "✅", fail: "❌", skip: "–" }.freeze

  def self.check_app(j)
    a = (j["data"] || []).first
    return Result.new("app", "앱", :fail, "번들 ID로 앱을 못 찾음", "fastlane create_app") unless a
    Result.new("app", "앱", :ok, "#{a.dig('attributes', 'name')} · #{a.dig('attributes', 'bundleId')} (id #{a['id']})", nil)
  end

  def self.check_version(j)
    v = (j["data"] || []).first
    return Result.new("version", "버전", :fail, "App Store 버전 없음", "ASC 웹 › 앱 › + 버전 만들기") unless v
    Result.new("version", "버전", :ok, "#{v.dig('attributes', 'versionString')} · #{v.dig('attributes', 'appStoreState')}", nil)
  end

  def self.check_build(j)
    b = j["data"]
    return Result.new("build", "빌드", :fail, "버전에 첨부된 빌드 없음", "fastlane attach_build") unless b
    st = b.dig("attributes", "processingState")
    return Result.new("build", "빌드", :fail, "빌드 #{b.dig('attributes', 'version')} 처리 중(#{st})", "몇 분 뒤 다시 실행") if st != "VALID"
    Result.new("build", "빌드", :ok, "빌드 #{b.dig('attributes', 'version')} 첨부됨", nil)
  end

  def self.check_iaps(j)
    items = j["data"] || []
    return [Result.new("iap", "IAP", :skip, "앱 내 구입 없음", nil)] if items.empty?
    items.map do |i|
      pid = i.dig("attributes", "productId"); st = i.dig("attributes", "state")
      missing = []
      missing << "심사 스크린샷 없음" if i.dig("relationships", "appStoreReviewScreenshot", "data").nil?
      missing << "현지화 없음" if (i.dig("relationships", "inAppPurchaseLocalizations", "data") || []).empty?
      if st == "MISSING_METADATA" || !missing.empty?
        Result.new("iap", "IAP", :fail, "#{pid} #{st}: #{missing.empty? ? '누락 항목은 ASC 웹에서 확인' : missing.join(', ')}",
                   "fastlane iap_screenshot iap_id:#{i['id']} path:<png>")
      else
        Result.new("iap", "IAP", :ok, "#{pid} #{st}", nil)
      end
    end
  end

  def self.check_age_rating(j)
    attrs = j.dig("data", "attributes") || {}
    missing = AGE_KEYS.select { |k| attrs[k].nil? }
    return Result.new("age", "연령등급", :fail, "선언 항목 #{missing.size}개 비어 있음", "fastlane age_rating") unless missing.empty?
    Result.new("age", "연령등급", :ok, "선언 완료", nil)
  end

  def self.check_review_detail(j)
    a = j.dig("data", "attributes") || {}
    empty = %w[contactFirstName contactLastName contactEmail contactPhone].select { |k| a[k].to_s.strip.empty? }
    return Result.new("review", "심사정보", :fail, "비어 있음: #{empty.join(', ')}", "fastlane/metadata/review_information/*.txt 채우고 fastlane release_metadata") unless empty.empty?
    return Result.new("review", "심사정보", :fail, "전화는 E.164 형식(예 +821012345678)", "review_information/phone_number.txt 수정") unless a["contactPhone"].to_s.start_with?("+")
    Result.new("review", "심사정보", :ok, "연락처 채워짐", nil)
  end

  def self.check_screenshots(j)
    ok = (j["data"] || []).any? do |s|
      %w[APP_IPHONE_67 APP_IPHONE_65].include?(s.dig("attributes", "screenshotDisplayType")) &&
        !(s.dig("relationships", "appScreenshots", "data") || []).empty?
    end
    return Result.new("shots", "스크린샷", :ok, "6.9″/6.5″ 세트 있음", nil) if ok
    Result.new("shots", "스크린샷", :fail, "6.9″(또는 6.5″) iPhone 스크린샷 없음", "fastlane upload_screenshots")
  end

  def self.check_metadata(j)
    l = (j["data"] || []).first
    return Result.new("meta", "메타", :fail, "로케일 없음", "fastlane release_metadata") unless l
    a = l["attributes"] || {}
    empty = %w[description keywords supportUrl].select { |k| a[k].to_s.strip.empty? }
    return Result.new("meta", "메타", :fail, "#{a['locale']} 비어 있음: #{empty.join(', ')}", "fastlane/metadata/<locale>/*.txt 채우고 fastlane release_metadata") unless empty.empty?
    Result.new("meta", "메타", :ok, "#{a['locale']} 설명·키워드·지원 URL 있음", nil)
  end

  def self.check_privacy_url(j)
    l = (j["data"] || []).first
    url = l&.dig("attributes", "privacyPolicyUrl").to_s
    return Result.new("privacy", "개인정보", :fail, "개인정보처리방침 URL 없음", "fastlane/metadata/<locale>/privacy_url.txt 채우고 fastlane release_metadata") if url.strip.empty?
    Result.new("privacy", "개인정보", :ok, url, nil)
  end

  def self.check_encryption(path)
    return Result.new("enc", "암호화", :skip, "Info.plist 경로 없음(INFO_PLIST 미설정)", nil) if path.nil? || !File.exist?(path)
    return Result.new("enc", "암호화", :ok, "ITSAppUsesNonExemptEncryption 있음", nil) if File.read(path, encoding: "UTF-8").include?("ITSAppUsesNonExemptEncryption")
    Result.new("enc", "암호화", :fail, "Info.plist에 ITSAppUsesNonExemptEncryption 없음(빌드마다 수출 규정 질문 뜸)", "Info.plist에 ITSAppUsesNonExemptEncryption=false 추가")
  end

  def self.check_submission(j, version_id)
    draft = (j["data"] || []).find { |d| %w[READY_FOR_REVIEW UNRESOLVED_ISSUES].include?(d.dig("attributes", "state")) }
    return Result.new("submit", "제출초안", :skip, "제출 초안 없음", nil) unless draft
    ids = (draft.dig("relationships", "items", "data") || []).map { |i| i["id"] }
    items = (j["included"] || []).select { |i| i["type"] == "reviewSubmissionItems" && ids.include?(i["id"]) }
    has = items.any? { |i| i.dig("relationships", "appStoreVersion", "data", "id") == version_id }
    return Result.new("submit", "제출초안", :ok, "초안에 앱 버전 포함", nil) if has
    Result.new("submit", "제출초안", :fail, "제출 초안에 앱 버전이 빠짐(이 상태로 제출하면 IAP만 감)", "ASC 웹 › 심사 제출 › 항목 추가 › 앱 버전")
  end

  def self.check_paid_agreement
    Result.new("paid", "유료계약", :skip, "API로 못 읽음. 유료 IAP면 ASC 웹 › 비즈니스 › 유료 앱 계약 활성 확인", nil)
  end

  def self.format(results)
    lines = results.map { |r| "#{ICON[r.status]} #{r.label.ljust(6)} #{r.message}#{r.fix ? " → #{r.fix}" : ''}" }
    fails = results.count { |r| r.status == :fail }
    lines << "❌ #{fails}개 · 제출 가능: #{fails.zero? ? '예' : '아니오'}"
    lines.join("\n")
  end
end
