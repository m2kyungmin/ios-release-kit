require "minitest/autorun"
require "tempfile"
require "kit_env"

class KitEnvTest < Minitest::Test
  def test_load_fills_only_missing_keys
    f = Tempfile.new("env"); f.write("# 주석\nBUNDLE_ID=com.example.app\nASC_KEY_ID=ABCDE12345\n\n"); f.flush
    ENV["ASC_KEY_ID"] = "FROMSHELL"; ENV.delete("BUNDLE_ID")
    filled = KitEnv.load(f.path)
    assert_equal ["BUNDLE_ID"], filled
    assert_equal "FROMSHELL", ENV["ASC_KEY_ID"]
    assert_equal "com.example.app", ENV["BUNDLE_ID"]
  ensure
    ENV.delete("ASC_KEY_ID"); ENV.delete("BUNDLE_ID")
  end

  # 로케일이 UTF-8이 아니어도 한국어가 든 .env를 읽을 수 있어야 한다.
  # (09-11 fastlane deliver가 같은 자리에서 죽었다: String#strip, invalid byte sequence in US-ASCII)
  # KitEnv.load에서 encoding: "UTF-8"을 빼면 이 테스트가 어느 기계에서든 깨진다.
  def test_load_reads_utf8_under_ascii_locale
    prev = Encoding.default_external
    f = Tempfile.new("env"); f.write("# 한국어 주석\nBUNDLE_ID=com.example.app\n"); f.flush
    ENV.delete("BUNDLE_ID")
    silence_warnings { Encoding.default_external = Encoding::US_ASCII }
    assert_equal ["BUNDLE_ID"], KitEnv.load(f.path)
    assert_equal "com.example.app", ENV["BUNDLE_ID"]
  ensure
    silence_warnings { Encoding.default_external = prev }
    ENV.delete("BUNDLE_ID")
  end

  def silence_warnings
    prev = $VERBOSE; $VERBOSE = nil
    yield
  ensure
    $VERBOSE = prev
  end

  def test_require_raises_listing_missing
    ENV.delete("ZZ_A"); ENV["ZZ_B"] = "1"
    e = assert_raises(KitEnv::Missing) { KitEnv.require!("ZZ_A", "ZZ_B") }
    assert_includes e.message, "ZZ_A"
    refute_includes e.message, "ZZ_B"
  ensure
    ENV.delete("ZZ_B")
  end
end
