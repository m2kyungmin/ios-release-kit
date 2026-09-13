require "minitest/autorun"
require "json"
require "asc_doctor"

# «설정은 맞는데 StoreKit이 빈 배열을 준다»는 질문에 대해 우리가 확실히 판정할 수 있는 것:
# 앱이 요청하는 productId가 ASC에 실제로 존재하는가.
class ProductIdsTest < Minitest::Test
  def fx(name) = JSON.parse(File.read(File.join(__dir__, "fixtures", name), encoding: "UTF-8"))
  def asc(*ids) = { "data" => ids.map { |i| { "id" => "x", "attributes" => { "productId" => i } } } }

  def test_collects_ids_from_products_and_subscription_groups
    ids = AscDoctor.local_product_ids(fx("products.storekit"))
    assert_equal ["com.example.app.unlock", "com.example.app.pro.monthly", "com.example.app.pro.yearly"].sort, ids.sort
  end

  def test_ignores_non_string_and_blank_ids
    ids = AscDoctor.local_product_ids({ "products" => [{ "productID" => "" }, { "productID" => nil }, { "productID" => "ok" }] })
    assert_equal ["ok"], ids
  end

  def test_dedupes
    ids = AscDoctor.local_product_ids({ "a" => [{ "productID" => "x" }], "b" => [{ "productID" => "x" }] })
    assert_equal ["x"], ids
  end

  def test_all_matching_is_ok
    r = AscDoctor.check_product_ids(asc("a", "b"), ["a", "b"])
    assert_equal :ok, r.status
    assert_includes r.message, "전부 일치"
  end

  def test_id_only_in_storekit_is_the_empty_array_cause
    r = AscDoctor.check_product_ids(asc("a"), ["a", "com.example.typo"])
    assert_equal :fail, r.status
    assert_includes r.message, "com.example.typo"
    assert_includes r.message, "빈 배열"
    refute_nil r.fix
  end

  def test_id_only_in_asc_is_reported_but_not_a_failure
    r = AscDoctor.check_product_ids(asc("a", "legacy"), ["a"])
    assert_equal :ok, r.status
    assert_includes r.message, "legacy"
  end

  def test_no_storekit_file_skips
    assert_equal :skip, AscDoctor.check_product_ids(asc("a"), nil).status
  end

  def test_empty_storekit_skips
    assert_equal :skip, AscDoctor.check_product_ids(asc("a"), []).status
  end

  def test_hint_is_informational_only
    r = AscDoctor.storekit_hint
    assert_equal :skip, r.status, "안내는 제출 가능 판정을 바꾸면 안 된다"
    assert_includes r.message, "유료 앱 계약"
    assert_includes r.message, "전파 지연"
  end

  def test_state_values_are_never_interpreted
    # ASC state 는 그대로 출력만 한다. 모르는 상태에 의미를 붙이지 않는다.
    src = File.read(File.join(__dir__, "..", "fastlane", "lib", "asc_doctor.rb"), encoding: "UTF-8")
    %w[READY_TO_SUBMIT APPROVED DEVELOPER_ACTION_NEEDED PENDING_BINARY_APPROVAL].each do |st|
      refute_includes src, st, "확인하지 않은 상태값 #{st} 에 의미를 붙이면 안 된다"
    end
  end
end
