# frozen_string_literal: true

require "test_helper"

class GenerationProgressBroadcastableTest < ActiveSupport::TestCase
  test "calculates prompt and image elapsed seconds separately" do
    generation = ImageGeneration.new(
      japanese_prompt: "test",
      sd_model: "flat2d",
      loras: "[]",
      status: "completed",
      prompt_started_at: 120.seconds.ago,
      prompt_finished_at: 90.seconds.ago,
      image_started_at: 80.seconds.ago,
      image_finished_at: 20.seconds.ago
    )

    assert_in_delta 30.0, generation.prompt_elapsed_seconds, 0.5
    assert_in_delta 60.0, generation.image_elapsed_seconds, 0.5
  end

  test "uses current time for active prompt phase" do
    generation = ImageGeneration.new(
      japanese_prompt: "test",
      sd_model: "flat2d",
      loras: "[]",
      status: "translating",
      prompt_started_at: 5.seconds.ago
    )

    assert generation.prompt_phase_active?
    assert_in_delta 5.0, generation.prompt_elapsed_seconds, 0.5
    assert_nil generation.image_elapsed_seconds
  end

  test "uses current time for active image phase" do
    generation = ImageGeneration.new(
      japanese_prompt: "test",
      sd_model: "flat2d",
      loras: "[]",
      status: "drafting",
      prompt_started_at: 30.seconds.ago,
      prompt_finished_at: 20.seconds.ago,
      image_started_at: 10.seconds.ago
    )

    assert_not generation.prompt_phase_active?
    assert generation.image_phase_active?
    assert_in_delta 10.0, generation.image_elapsed_seconds, 0.5
    assert_in_delta 10.0, generation.prompt_elapsed_seconds, 0.5
  end

  test "prompt phase is inactive after prompt_finished_at is set" do
    generation = ImageGeneration.new(
      japanese_prompt: "test",
      sd_model: "flat2d",
      loras: "[]",
      status: "translating",
      prompt_started_at: 10.seconds.ago,
      prompt_finished_at: 5.seconds.ago
    )

    assert_not generation.prompt_phase_active?
    assert_in_delta 5.0, generation.prompt_elapsed_seconds, 0.5
  end
end
