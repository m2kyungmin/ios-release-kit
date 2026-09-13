module KitEnv
  class Missing < StandardError; end

  def self.load(path)
    return [] unless File.exist?(path)
    File.readlines(path, encoding: "UTF-8").filter_map do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#") || !line.include?("=")
      k, v = line.split("=", 2)
      next if ENV.key?(k)
      ENV[k] = v.strip.delete_prefix('"').delete_suffix('"')
      k
    end
  end

  def self.require!(*keys)
    missing = keys.select { |k| ENV[k].to_s.strip.empty? }
    raise Missing, "fastlane/.env 에 없음: #{missing.join(', ')} (fastlane/.env.template 참고)" unless missing.empty?
  end
end
