require "minitest/autorun"
require "iap_screenshot"

class IapScreenshotTest < Minitest::Test
  def test_chunks_follow_offsets
    data = "abcdefghij"
    ops = [{ "offset" => 0, "length" => 4 }, { "offset" => 4, "length" => 6 }]
    assert_equal %w[abcd efghij], IapScreenshot.chunks(data, ops)
  end

  def test_checksum_is_md5_hex
    assert_equal "900150983cd24fb0d6963f7d28e17f72", IapScreenshot.checksum("abc")
  end

  FakeClient = Struct.new(:calls) do
    def get(path, params = {}) = (calls << [:get, path]; [200, { "data" => nil }])
    def post(path, body)  = (calls << [:post, path, body]; [201, { "data" => { "id" => "S1", "attributes" => { "uploadOperations" => [] } } }])
    def patch(path, body) = (calls << [:patch, path, body]; [200, { "data" => { "attributes" => { "assetDeliveryState" => { "state" => "UPLOAD_COMPLETE" } } } }])
    def delete(path)      = (calls << [:delete, path]; [204, {}])
  end

  def test_upload_reserves_then_commits
    png = File.join(__dir__, "fixtures", "tiny.png")
    File.binwrite(png, "\x89PNG\r\n\x1a\n") unless File.exist?(png)
    c = FakeClient.new([])
    r = IapScreenshot.upload(c, iap_id: "1111", png_path: png)
    assert_equal "S1", r["id"]
    assert_equal :post, c.calls[1][0]
    assert_equal "inAppPurchaseAppStoreReviewScreenshots", c.calls[1][1]
    assert_equal "1111", c.calls[1][2][:data][:relationships][:inAppPurchaseV2][:data][:id]
    assert_equal :patch, c.calls.last[0]
    assert_equal true, c.calls.last[2][:data][:attributes][:uploaded]
    assert_equal "UPLOAD_COMPLETE", r["state"]
  end

  class FailingCommitClient < FakeClient
    def patch(path, body) = (calls << [:patch, path, body]; [409, { "errors" => [{ "detail" => "x" }] }])
  end

  def test_upload_raises_when_commit_fails
    png = File.join(__dir__, "fixtures", "tiny.png")
    c = FailingCommitClient.new([])
    err = assert_raises(RuntimeError) { IapScreenshot.upload(c, iap_id: "1111", png_path: png) }
    assert_includes err.message, "커밋 실패 HTTP 409"
  end

  class ExistingScreenshotClient < FakeClient
    def get(path, params = {}) = (calls << [:get, path]; [200, { "data" => { "id" => "OLD" } }])
  end

  def test_upload_deletes_existing_screenshot
    png = File.join(__dir__, "fixtures", "tiny.png")
    c = ExistingScreenshotClient.new([])
    IapScreenshot.upload(c, iap_id: "1111", png_path: png)
    assert_includes c.calls, [:delete, "inAppPurchaseAppStoreReviewScreenshots/OLD"]
    delete_i = c.calls.index([:delete, "inAppPurchaseAppStoreReviewScreenshots/OLD"])
    post_i = c.calls.index { |call| call[0] == :post }
    assert delete_i < post_i, "delete must happen before post"
  end
end
