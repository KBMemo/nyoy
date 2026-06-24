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
end
