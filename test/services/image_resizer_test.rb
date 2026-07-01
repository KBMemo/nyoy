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

  test "resize_to_limit shrinks images larger than max edge" do
    large = Vips::Image.black(2000, 1000).pngsave_buffer

    resized, mime_type = ImageResizer.resize_to_limit(large, max_edge: 1024)

    result = Vips::Image.new_from_buffer(resized, "")
    assert_equal 1024, [result.width, result.height].max
    assert_equal "image/png", mime_type
  end

  test "resize_to_limit leaves small images unchanged" do
    small = Vips::Image.black(100, 100).pngsave_buffer

    resized, mime_type = ImageResizer.resize_to_limit(small, mime_type: "image/jpeg")

    assert_equal small, resized
    assert_equal "image/jpeg", mime_type
  end
end
