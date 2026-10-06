require "minitest/autorun"
require "json"
require "asc_doctor"
require "tmpdir"
require "fileutils"

class AscDoctorTest < Minitest::Test
  def fx(name) = JSON.parse(File.read(File.join(__dir__, "fixtures", name), encoding: "UTF-8"))

  def test_app_missing_is_fail_with_create_fix
    r = AscDoctor.check_app({ "data" => [] })
    assert_equal :fail, r.status
    assert_equal "fastlane create_app", r.fix
  end

  def test_app_present_is_ok
    r = AscDoctor.check_app({ "data" => [{ "id" => "1", "attributes" => { "bundleId" => "com.example.app", "name" => "Ex" } }] })
    assert_equal :ok, r.status
    assert_includes r.message, "com.example.app"
  end

  def test_build_missing_is_fail
    r = AscDoctor.check_build({ "data" => nil })
    assert_equal :fail, r.status
    assert_equal "fastlane attach_build", r.fix
  end

  def test_build_processing_is_fail
    r = AscDoctor.check_build({ "data" => { "id" => "b", "attributes" => { "version" => "2", "processingState" => "PROCESSING" } } })
    assert_equal :fail, r.status
  end

  def test_iap_missing_screenshot_lists_reason
    rs = AscDoctor.check_iaps(fx("iaps_missing_screenshot.json"))
    assert_equal 1, rs.size
    assert_equal :fail, rs[0].status
    assert_includes rs[0].message, "심사 스크린샷 없음"
    assert_includes rs[0].fix, "iap_id:1111"
  end

  def test_iap_none_is_skip
    assert_equal :skip, AscDoctor.check_iaps({ "data" => [] })[0].status
  end

  def test_age_rating_empty_is_fail
    r = AscDoctor.check_age_rating(fx("age_rating_empty.json"))
    assert_equal :fail, r.status
    assert_equal "fastlane age_rating", r.fix
  end

  def test_age_rating_full_is_ok
    assert_equal 23, AscDoctor::AGE_KEYS.size
    attrs = AscDoctor::AGE_KEYS.to_h { |k| [k, k.start_with?("violence", "sexual", "profanity", "horror", "mature", "medical", "alcohol", "contests", "gamblingSimulated", "guns") ? "NONE" : false] }
    r = AscDoctor.check_age_rating({ "data" => { "attributes" => attrs } })
    assert_equal :ok, r.status
  end

  def test_review_phone_must_be_e164
    base = { "contactFirstName" => "A", "contactLastName" => "B", "contactEmail" => "a@b.c" }
    bad = AscDoctor.check_review_detail({ "data" => { "attributes" => base.merge("contactPhone" => "01012345678") } })
    good = AscDoctor.check_review_detail({ "data" => { "attributes" => base.merge("contactPhone" => "+821012345678") } })
    assert_equal :fail, bad.status
    assert_equal :ok, good.status
  end

  def test_screenshots_need_67_or_65
    sets = { "data" => [{ "id" => "s", "attributes" => { "screenshotDisplayType" => "APP_IPHONE_67" }, "relationships" => { "appScreenshots" => { "data" => [{ "id" => "x" }] } } }] }
    assert_equal :ok, AscDoctor.check_screenshots(sets).status
    assert_equal :fail, AscDoctor.check_screenshots({ "data" => [] }).status
  end

  def test_submission_without_version_item_is_fail
    subs = { "data" => [{ "id" => "r", "attributes" => { "state" => "READY_FOR_REVIEW" }, "relationships" => { "items" => { "data" => [{ "id" => "i1" }] } } }],
             "included" => [{ "type" => "reviewSubmissionItems", "id" => "i1", "relationships" => { "appStoreVersion" => { "data" => nil } } }] }
    assert_equal :fail, AscDoctor.check_submission(subs, "v1").status
    subs["included"][0]["relationships"]["appStoreVersion"]["data"] = { "id" => "v1" }
    assert_equal :ok, AscDoctor.check_submission(subs, "v1").status
    assert_equal :skip, AscDoctor.check_submission({ "data" => [] }, "v1").status
  end

  def test_format_counts_failures
    out = AscDoctor.format([AscDoctor::Result.new("a", "앱", :ok, "x", nil), AscDoctor::Result.new("b", "빌드", :fail, "없음", "fastlane attach_build")])
    assert_includes out, "✅ 앱"
    assert_includes out, "❌ 빌드"
    assert_includes out, "→ fastlane attach_build"
    assert_includes out, "❌ 1개 · 제출 가능: 아니오"
  end

  PLIST_NO = "<dict>\n<key>ITSAppUsesNonExemptEncryption</key>\n<false/>\n</dict>"
  PLIST_YES = "<dict>\n<key>ITSAppUsesNonExemptEncryption</key>\n<true/>\n</dict>"

  # 임시 프로젝트: Info.plist 하나와 소스 파일들({상대경로 => 내용})
  def with_project(plist, sources = {})
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Info.plist"), plist)
      sources.each do |rel, body|
        FileUtils.mkdir_p(File.dirname(File.join(dir, rel)))
        File.write(File.join(dir, rel), body)
      end
      yield File.join(dir, "Info.plist"), dir
    end
  end

  def test_encryption_key_missing_is_fail
    with_project("<dict></dict>") { |pl, dir| assert_equal :fail, AscDoctor.check_encryption(pl, dir).status }
  end

  def test_encryption_no_with_hash_only_is_ok
    with_project(PLIST_NO, "App/Id.swift" => "import CryptoKit\nlet d = Insecure.MD5.hash(data: x)\n") do |pl, dir|
      r = AscDoctor.check_encryption(pl, dir)
      assert_equal :ok, r.status
      assert_includes r.message, "해시만"
      assert_includes r.message, "App/Id.swift:2"
    end
  end

  def test_encryption_no_with_cipher_is_warn_with_location
    with_project(PLIST_NO, "App/Vault.swift" => "import CryptoKit\nlet box = try AES.GCM.seal(data, using: key)\n") do |pl, dir|
      r = AscDoctor.check_encryption(pl, dir)
      assert_equal :warn, r.status
      assert_includes r.message, "App/Vault.swift:2 AES.GCM"
      assert_includes r.fix, "USES_ENCRYPTION=true"
    end
  end

  def test_encryption_scan_ignores_comments_and_pods
    src = { "App/A.swift" => "// AES.GCM 은 안 씀\n", "Pods/Lib/B.swift" => "AES.GCM.seal(x, using: k)\n" }
    with_project(PLIST_NO, src) { |pl, dir| assert_equal :ok, AscDoctor.check_encryption(pl, dir).status }
  end

  def test_encryption_yes_needs_env_true
    with_project(PLIST_YES) do |pl, dir|
      assert_equal :warn, AscDoctor.check_encryption(pl, dir, nil).status
      assert_equal :ok, AscDoctor.check_encryption(pl, dir, "true").status
    end
  end

  def test_encryption_no_with_env_true_is_warn
    with_project(PLIST_NO) { |pl, dir| assert_equal :warn, AscDoctor.check_encryption(pl, dir, "true").status }
  end

  def test_format_warn_does_not_block_submit
    out = AscDoctor.format([AscDoctor::Result.new("enc", "암호화", :warn, "x", "y")])
    assert_includes out, "⚠️ 암호화"
    assert_includes out, "⚠️ 1개 확인 필요"
    assert_includes out, "❌ 0개 · 제출 가능: 예"
  end
end
