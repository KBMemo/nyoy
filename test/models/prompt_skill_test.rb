# frozen_string_literal: true

require "test_helper"

class PromptSkillTest < ActiveSupport::TestCase
  test "keeps only one default skill" do
    first = PromptSkill.create!(name: "A", body: "body a", default: true)
    second = PromptSkill.create!(name: "B", body: "body b", default: true)

    assert_not first.reload.default?
    assert second.reload.default?
  end
end
