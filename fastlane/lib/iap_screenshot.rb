require "digest"
require "net/http"
require "uri"

# IAP 심사 스크린샷: reserve → 청크 업로드 → commit.
module IapScreenshot
  TYPE = "inAppPurchaseAppStoreReviewScreenshots"

  def self.chunks(data, ops) = ops.map { |op| data[op["offset"], op["length"]] }
  def self.checksum(data)    = Digest::MD5.hexdigest(data)

  # 0 = dry-run(AscClient#write), 2xx = 성공
  def self.ok?(code) = code.zero? || (200..299).cover?(code)

  def self.upload(client, iap_id:, png_path:)
    data = File.binread(png_path)
    _, existing = client.get("inAppPurchasesV2/#{iap_id}/appStoreReviewScreenshot")
    if existing["data"]
      dcode, dbody = client.delete("#{TYPE}/#{existing['data']['id']}")
      raise "기존 스크린샷 삭제 실패 HTTP #{dcode}: #{dbody.to_s[0, 300]}" unless ok?(dcode)
    end

    pcode, res = client.post(TYPE, { data: { type: TYPE,
      attributes: { fileName: File.basename(png_path), fileSize: data.bytesize },
      relationships: { inAppPurchaseV2: { data: { type: "inAppPurchases", id: iap_id } } } } })
    return { "id" => nil, "chunks" => 0, "state" => "dry_run" } if res["dry_run"]
    raise "reserve 실패 HTTP #{pcode}: #{res.to_s[0, 300]}" unless ok?(pcode)

    sid = res.dig("data", "id") or raise "reserve 실패: #{res}"
    ops = res.dig("data", "attributes", "uploadOperations") || []
    chunks(data, ops).each_with_index do |chunk, i|
      op = ops[i]
      req = Net::HTTP.const_get(op["method"].capitalize).new(URI(op["url"]))
      (op["requestHeaders"] || []).each { |h| req[h["name"]] = h["value"] }
      req.body = chunk
      code = Net::HTTP.start(req.uri.host, req.uri.port, use_ssl: true, read_timeout: 120) { |h| h.request(req) }.code.to_i
      raise "청크 #{i} 업로드 실패 HTTP #{code}" unless [200, 201, 204].include?(code)
    end

    ccode, done = client.patch("#{TYPE}/#{sid}", { data: { type: TYPE, id: sid, attributes: { uploaded: true, sourceFileChecksum: checksum(data) } } })
    raise "스크린샷 커밋 실패 HTTP #{ccode}: #{done.to_s[0, 300]}" unless ok?(ccode)
    { "id" => sid, "chunks" => ops.size, "state" => done.dig("data", "attributes", "assetDeliveryState", "state") }
  end
end
