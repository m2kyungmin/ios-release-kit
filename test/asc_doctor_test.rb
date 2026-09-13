require "minitest/autorun"
require "json"
require "asc_doctor"

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
end
