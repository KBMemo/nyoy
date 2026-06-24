# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "nyoy_blob_image_path uses relative path for attached blob" do
    generation = ImageGeneration.create!(
      japanese_prompt: "test",
      sd_model: "flat2d",
      loras: "[]"
    )
    generation.image.attach(
      io: StringIO.new("fake"),
      filename: "test.png",
      content_type: "image/png"
    )

    path = nyoy_blob_image_path(generation.image)

    assert path.start_with?("/rails/active_storage/")
    assert_not path.include?("example.org")
  end

  test "nyoy_format_seed shows random label for blank or negative values" do
    assert_equal "ランダム", nyoy_format_seed(nil)
    assert_equal "ランダム", nyoy_format_seed(-1)
    assert_equal "42", nyoy_format_seed(42)
  end
end
