require "net/http"
require "json"
require "uri"

# App Store Connect REST 얇은 클라이언트. 토큰은 메모리에만 둔다.
class AscClient
  BASE = "https://api.appstoreconnect.apple.com/v1/"

  def self.encode_query(params)
    params.map { |k, v| "#{URI.encode_www_form_component(k.to_s)}=#{URI.encode_www_form_component(v.to_s)}" }.join("&")
  end

  def self.dry_run? = ENV["DRY_RUN"] == "1"

  def self.parse_body(raw)
    return {} if raw.nil? || raw.strip.empty?
    JSON.parse(raw)
  rescue JSON::ParserError
    { "raw" => raw[0, 300] }
  end

  def initialize(token) = @token = token

  def get(path, params = {})
    q = params.empty? ? "" : "?#{self.class.encode_query(params)}"
    request(Net::HTTP::Get.new(URI(BASE + path + q)))
  end

  def post(path, body)   = write(Net::HTTP::Post,   "POST",   path, body)
  def patch(path, body)  = write(Net::HTTP::Patch,  "PATCH",  path, body)
  def delete(path)       = write(Net::HTTP::Delete, "DELETE", path, nil)

  private

  def write(klass, method, path, body)
    return [0, { "dry_run" => { "method" => method, "path" => path, "body" => body } }] if self.class.dry_run?
    req = klass.new(URI(BASE + path))
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    request(req)
  end

  def request(req)
    req["Authorization"] = "Bearer #{@token}"
    uri = req.uri
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 60) { |h| h.request(req) }
    [res.code.to_i, self.class.parse_body(res.body.to_s.force_encoding("UTF-8"))]
  end
end
