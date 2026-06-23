# frozen_string_literal: true

require "test_helper"

class ImageGenerationTest < ActiveSupport::TestCase
  test "requires japanese prompt and sd model" do
    generation = ImageGeneration.new
    assert_not generation.valid?
    assert_includes generation.errors[:japanese_prompt], "can't be blank"
    assert_includes generation.errors[:sd_model], "can't be blank"
  end

  test "defaults status to pending" do
    generation = ImageGeneration.new(
      japanese_prompt: "テスト",
      sd_model: "flat2d"
    )
    assert_equal "pending", generation.status
  end
end
