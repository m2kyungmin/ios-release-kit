require "time"

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

  # «설정은 맞는데 StoreKit이 상품을 빈 배열로 돌려준다»는 커뮤니티 최다 질문 중 하나다.
  # 우리가 확인할 수 있는 건 하나뿐이라 그것만 판정한다: 앱이 요청하는 productId가 ASC에 실제로 있는가.
  # 나머지 원인(유료 앱 계약·전파 지연)은 API로 못 읽으므로 확인 순서만 안내한다.
  # ASC의 상품 state 값은 그대로 출력만 하고 의미를 지어내지 않는다.

  # .storekit 설정 파일에서 productID를 전부 긁어온다.
  # products[] 와 subscriptionGroups[] 의 스키마를 각각 가정하지 않고 트리를 훑는다.
  def self.local_product_ids(node, acc = [])
    case node
    when Hash
      node.each do |k, v|
        acc << v if k == "productID" && v.is_a?(String) && !v.strip.empty?
        local_product_ids(v, acc)
      end
    when Array
      node.each { |v| local_product_ids(v, acc) }
    end
    acc.uniq
  end

  def self.check_product_ids(iap_json, local_ids)
    asc = (iap_json["data"] || []).map { |i| i.dig("attributes", "productId") }.compact.uniq
    return Result.new("pid", "상품ID", :skip, ".storekit 설정 파일을 못 찾음(STOREKIT_CONFIG 미설정)", nil) if local_ids.nil?
    return Result.new("pid", "상품ID", :skip, ".storekit에 상품 없음", nil) if local_ids.empty?

    only_local = local_ids - asc
    only_asc   = asc - local_ids

    unless only_local.empty?
      return Result.new("pid", "상품ID", :fail,
                        ".storekit에만 있음: #{only_local.join(', ')} — ASC에 이 productId가 없어서 앱이 요청하면 빈 배열이 온다",
                        "ASC에서 같은 productId로 상품을 만들거나, 앱·.storekit의 id를 ASC와 맞춘다")
    end

    msg = ".storekit #{local_ids.size}개 · ASC #{asc.size}개 · 전부 일치"
    msg += " (ASC에만: #{only_asc.join(', ')})" unless only_asc.empty?
    Result.new("pid", "상품ID", :ok, msg, nil)
  end

  # 상품ID가 맞는데도 빈 배열이면 남은 원인은 API로 못 읽는다. 순서만 안내한다.
  def self.storekit_hint
    Result.new("sk", "StoreKit", :skip,
               "상품이 빈 배열로 오면 확인 순서: ① 위 상품ID 일치 ② 유료 앱 계약 활성(ASC 웹 › 비즈니스, API로 못 읽음) ③ ASC 변경 직후면 전파 지연",
               nil)
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

  # 심사 제출은 됐는데 그 다음이 안 보일 때. 커뮤니티 1위 질문("내 대기가 정상인가")에 대한 답은
  # "정상/비정상"이 아니라 ① 지금 애플 큐에 들어가 있기는 한가 ② 들어갔다면 며칠째인가 두 가지다.
  QUEUE_STATES = %w[WAITING_FOR_REVIEW IN_REVIEW].freeze
  DRAFT_STATES = %w[READY_FOR_REVIEW UNRESOLVED_ISSUES].freeze
  DONE_STATES  = %w[COMPLETING COMPLETE].freeze
  INQUIRY_DAYS = 7

  def self.elapsed_label(from, now)
    secs = now.to_i - from.to_i
    return "방금" if secs < 0
    secs < 86_400 ? "#{secs / 3600}시간째" : "#{secs / 86_400}일째"
  end

  def self.latest_submission(subs)
    subs.max_by { |d| Time.iso8601(d.dig("attributes", "submittedDate").to_s).to_i rescue 0 }
  end

  def self.check_review_progress(j, now = Time.now)
    subs = j["data"] || []
    if subs.empty?
      return Result.new("progress", "심사진행", :skip,
                        "심사에 제출한 이력 없음 — 애플 큐에 들어가 있지 않다", nil)
    end

    sub = latest_submission(subs)
    state = sub.dig("attributes", "state").to_s
    raw   = sub.dig("attributes", "submittedDate").to_s

    if DRAFT_STATES.include?(state)
      note = state == "UNRESOLVED_ISSUES" ? "해결 안 된 항목이 있어 제출이 막혀 있다" : "제출 초안만 만들어져 있고 아직 제출되지 않았다"
      return Result.new("progress", "심사진행", :skip,
                        "아직 애플 큐에 없음(#{state}) — #{note}", "위 항목들을 먼저 해결한 뒤 ASC 웹 › 심사 제출")
    end

    submitted = (Time.iso8601(raw) rescue nil)
    if submitted.nil?
      return Result.new("progress", "심사진행", :ok, "상태 #{state}(제출 시각 없음)", nil)
    end

    stamp = submitted.getlocal.strftime("%Y-%m-%d %H:%M")
    days  = (now.to_i - submitted.to_i) / 86_400

    if DONE_STATES.include?(state)
      return Result.new("progress", "심사진행", :ok, "심사 종료(#{state}) · 제출 #{stamp}", nil)
    end

    label = state == "IN_REVIEW" ? "심사 중" : "애플 큐에서 대기"
    msg   = "#{label} #{elapsed_label(submitted, now)} · 제출 #{stamp} (#{state})"
    fix   = days >= INQUIRY_DAYS ? "#{INQUIRY_DAYS}일 넘음 — ASC 웹 › 문의하기 › App Review로 상태 문의 가능" : nil
    Result.new("progress", "심사진행", :ok, msg, fix)
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
