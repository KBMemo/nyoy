# frozen_string_literal: true

require "test_helper"

class ImageResizerTest < ActiveSupport::TestCase
  test "resize_png returns target dimensions" do
  # 1x1 red PNG
    png = Base64.decode64(
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )

    resized = ImageResizer.resize_png(png, width: 64, height: 64)

    assert_operator resized.bytesize, :>, png.bytesize
  end
end
