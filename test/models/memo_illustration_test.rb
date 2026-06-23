# frozen_string_literal: true

require "test_helper"

class MemoIllustrationTest < ActiveSupport::TestCase
  setup do
    @skill = PromptSkill.create!(name: "Test Skill", body: "system prompt", default: true)
  end

  test "requires body and sd model" do
    illustration = MemoIllustration.new(prompt_skill: @skill)
    assert_not illustration.valid?
    assert_includes illustration.errors[:body], "can't be blank"
    assert_includes illustration.errors[:sd_model], "can't be blank"
  end
end
