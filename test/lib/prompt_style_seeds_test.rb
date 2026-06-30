# frozen_string_literal: true

require "test_helper"

class PromptStyleSeedsTest < ActiveSupport::TestCase
  test "seeds watercolor still life style" do
    PromptStyleSeeds.seed!

    style = PromptStyle.find_by!(style_id: "watercolor_still_life")
    assert_equal "水彩静物画", style.name
    assert_includes style.prompt_prefix, "watercolor still life painting"
    assert_includes style.aliases, "水彩静物画"
    assert_equal "illustrious_pencil-XL", style.default_model.key
    assert style.enabled?
  end
end
