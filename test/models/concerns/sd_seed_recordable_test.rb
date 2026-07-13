# frozen_string_literal: true

require "test_helper"

class SdSeedRecordableTest < ActiveSupport::TestCase
  test "record_actual_seed! persists value when seed was random" do
    generation = ImageGeneration.create!(
      prompt: "test",
      sd_model: "flat2d",
      loras: "[]",
      seed: nil
    )

    generation.record_actual_seed!(25)

    assert_equal 25, generation.reload.seed
  end

  test "record_actual_seed! does not overwrite explicit seed" do
    generation = ImageGeneration.create!(
      prompt: "test",
      sd_model: "flat2d",
      loras: "[]",
      seed: 99
    )

    generation.record_actual_seed!(25)

    assert_equal 99, generation.reload.seed
  end

  test "random_seed? treats nil and negative values as random" do
    generation = ImageGeneration.new(seed: nil)
    assert generation.random_seed?

    generation.seed = -1
    assert generation.random_seed?

    generation.seed = 42
    assert_not generation.random_seed?
  end
end
