# frozen_string_literal: true

class ImageDataUrlDecoder
  class Error < StandardError; end

  def self.decode(data_url)
    new(data_url).decode
  end

  def initialize(data_url)
    @data_url = data_url.to_s
  end

  def decode
    encoded = @data_url.sub(/\Adata:image\/\w+;base64,/, "")
    data = Base64.decode64(encoded)
    raise Error, "画像データが空です" if data.blank?

    data
  end
end
