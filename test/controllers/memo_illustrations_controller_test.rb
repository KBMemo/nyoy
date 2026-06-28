# frozen_string_literal: true

require "test_helper"

class MemoIllustrationsControllerTest < ActionDispatch::IntegrationTest
  test "new renders the style form" do
    get new_memo_illustration_path
    assert_response :success
  end

  test "create enqueues a job and redirects with a chosen style" do
    assert_enqueued_with(job: GenerateMemoIllustrationJob) do
      post memo_illustrations_path, params: {
        memo_illustration: { body: "カフェのメモ", style_id: prompt_styles(:chojugiga).style_id }
      }
    end

    illustration = MemoIllustration.order(:created_at).last
    assert_equal "カフェのメモ", illustration.body
    assert_equal prompt_styles(:chojugiga).style_id, illustration.style_id
    assert_redirected_to memo_illustration_path(illustration)
  end

  test "create allows blank style_id for auto selection" do
    assert_enqueued_with(job: GenerateMemoIllustrationJob) do
      post memo_illustrations_path, params: {
        memo_illustration: { body: "メモ", style_id: "" }
      }
    end

    assert MemoIllustration.order(:created_at).last.style_id.blank?
  end

  test "create rejects blank body" do
    assert_no_enqueued_jobs do
      post memo_illustrations_path, params: { memo_illustration: { body: "" } }
    end
    assert_response :unprocessable_entity
  end
end
