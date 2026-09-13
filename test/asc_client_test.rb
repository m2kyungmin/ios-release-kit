require "minitest/autorun"
require "asc_client"

class AscClientTest < Minitest::Test
  def test_encode_query_escapes_brackets_and_commas
    q = AscClient.encode_query("filter[app]" => "1", "fields[builds]" => "version,processingState")
    assert_equal "filter%5Bapp%5D=1&fields%5Bbuilds%5D=version%2CprocessingState", q
  end

  def test_dry_run_returns_request_without_sending
    ENV["DRY_RUN"] = "1"
    status, body = AscClient.new("t").patch("appStoreVersions/v1/relationships/build", { data: { type: "builds", id: "b1" } })
    assert_equal 0, status
    assert_equal "PATCH", body["dry_run"]["method"]
    assert_equal "appStoreVersions/v1/relationships/build", body["dry_run"]["path"]
    assert_equal "b1", body["dry_run"]["body"][:data][:id]
  ensure
    ENV.delete("DRY_RUN")
  end

  def test_parse_body_empty_is_hash
    assert_equal({}, AscClient.parse_body(""))
    assert_equal({ "a" => 1 }, AscClient.parse_body('{"a":1}'))
    assert_equal({ "raw" => "<html>" }, AscClient.parse_body("<html>"))
  end
end
