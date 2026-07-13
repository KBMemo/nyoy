# frozen_string_literal: true

class SdCppGenerationInfo
  GenerationResult = Data.define(:images, :seed, :seeds)

  def self.parse(response)
    info = extract_info_hash(response)
    seeds = normalize_seeds(info)
    seed = seeds.first

    GenerationResult.new(images: [], seed: seed, seeds: seeds)
  end

  def self.decode_response(response)
    images = decode_images(response)
    parsed = parse(response)
    GenerationResult.new(images: images, seed: parsed.seed, seeds: parsed.seeds)
  end

  def self.extract_info_hash(response)
    info = response["info"]
    case info
    when String
      JSON.parse(info)
    when Hash
      info
    else
      {}
    end
  rescue JSON::ParserError
    {}
  end

  def self.normalize_seeds(info)
    seeds = Array(info["all_seeds"]).map { |value| Integer(value) rescue nil }.compact
    return seeds if seeds.any?

    seed = info["seed"]
    return [] if seed.nil?

    [Integer(seed)]
  rescue ArgumentError, TypeError
    []
  end

  def self.decode_images(response)
    images = response.fetch("images", []).map { |image_b64| Base64.decode64(image_b64) }
    raise SdCppClient::Error, "no image returned" if images.empty?

    images
  end
end
