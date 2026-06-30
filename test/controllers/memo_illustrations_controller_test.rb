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

  test "new copies body and style from copy_from" do
    illustration = MemoIllustration.create!(
      body: "カフェ、水彩画、テーブルの上にカフェラテ",
      style_id: prompt_styles(:chojugiga).style_id,
      status: "failed"
    )

    get new_memo_illustration_path(copy_from: illustration.id)

    assert_response :success
    assert_select "textarea[name='memo_illustration[body]']", text: /カフェ、水彩画/
    assert_select "select[name='memo_illustration[style_id]'] option[selected][value=?]",
                  prompt_styles(:chojugiga).style_id
  end

  test "destroy deletes illustration with confirmation flow" do
    illustration = MemoIllustration.create!(body: "削除テスト", status: "completed")

    assert_difference "MemoIllustration.count", -1 do
      delete memo_illustration_path(illustration)
    end

    assert_redirected_to memo_illustrations_path
    follow_redirect!
    assert_match "削除しました", response.body
  end

  test "destroy rejects in progress illustration" do
    illustration = MemoIllustration.create!(body: "生成中", status: "generating")

    assert_no_difference "MemoIllustration.count" do
      delete memo_illustration_path(illustration)
    end

    assert_redirected_to memo_illustrations_path
  end

  test "index delete button includes turbo confirm" do
    MemoIllustration.create!(body: "削除テスト", status: "completed")

    get root_path

    assert_response :success
    assert_select "form.nyoy-card-delete-form[data-controller=?]", "confirm-delete"
    assert_select "form[data-confirm-delete-message-value=?]", "このイラストを削除しますか？"
  end

  test "inpaint renders editor for completed illustration with image" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "completed")
    illustration.image.attach(io: StringIO.new("png"), filename: "source.png", content_type: "image/png")

    get inpaint_memo_illustration_path(illustration)

    assert_response :success
    assert_select "form[data-controller*='inpaint-mask']"
    assert_select "form[data-controller*='inpaint-form']"
    assert_select "input[name='source_attachment_id'][value=?]", illustration.image_attachment.id.to_s
  end

  test "inpaint defaults to original image when inpainted versions exist" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "completed")
    illustration.image.attach(io: StringIO.new("original"), filename: "source.png", content_type: "image/png")
    illustration.inpainted_images.attach(
      io: StringIO.new("inpainted"),
      filename: "inpaint-1.png",
      content_type: "image/png",
      metadata: { sequence: 1 }
    )

    get inpaint_memo_illustration_path(illustration)

    assert_response :success
    assert_select "input[name='source_attachment_id'][value=?]", illustration.image_attachment.id.to_s
  end

  test "inpaint can target a specific inpainted version" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "completed")
    illustration.image.attach(io: StringIO.new("original"), filename: "source.png", content_type: "image/png")
    illustration.inpainted_images.attach(
      io: StringIO.new("inpainted"),
      filename: "inpaint-1.png",
      content_type: "image/png",
      metadata: { sequence: 1 }
    )
    inpainted = illustration.inpainted_image_attachments.first

    get inpaint_memo_illustration_path(illustration, source_attachment_id: inpainted.id)

    assert_response :success
    assert_select "input[name='source_attachment_id'][value=?]", inpainted.id.to_s
  end

  test "translate_inpaint_note returns english fragment" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "completed")
    illustration.image.attach(io: StringIO.new("png"), filename: "source.png", content_type: "image/png")

    translator = Class.new do
      def translate(_note)
        "natural hands"
      end
    end.new

    original = InpaintNoteTranslator.method(:new)
    InpaintNoteTranslator.define_singleton_method(:new) { translator }

    post translate_inpaint_note_memo_illustration_path(illustration),
         params: { inpaint_note: "手を自然に" },
         as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "natural hands", body["translated_note"]
    assert body["translated"]
  ensure
    InpaintNoteTranslator.singleton_class.send(:define_method, :new, original) if defined?(original) && original
  end

  test "create_inpaint enqueues job" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "completed")
    illustration.image.attach(io: StringIO.new("png"), filename: "source.png", content_type: "image/png")
    mask = "data:image/png;base64,#{Base64.strict_encode64("mask")}"

    assert_enqueued_with(job: InpaintMemoIllustrationJob) do
      post inpaint_memo_illustration_path(illustration), params: {
        mask: mask,
        inpaint_prompt_delta: "natural hands",
        include_style_prefix: "1",
        denoising_strength: 0.5,
        source_attachment_id: illustration.image_attachment.id
      }
    end

    assert_redirected_to inpaint_memo_illustration_path(
      illustration,
      source_attachment_id: illustration.image_attachment.id,
      submitted: 1
    )
    illustration.reload
    assert_equal "inpainting", illustration.status
  end

  test "progress returns json status" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "inpainting", image_started_at: Time.current)

    get progress_memo_illustration_path(illustration), as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "inpainting", body["status"]
    assert_not body["finished"]
  end

  test "inpaint recovers stale inpainting and shows editor" do
    illustration = MemoIllustration.create!(
      body: "サッカーボール",
      status: "inpainting",
      image_started_at: 5.minutes.ago
    )
    illustration.image.attach(io: StringIO.new("png"), filename: "source.png", content_type: "image/png")

    get inpaint_memo_illustration_path(
      illustration,
      source_attachment_id: illustration.image_attachment.id
    )

    assert_response :success
    illustration.reload
    assert_equal "failed", illustration.status
    assert_select "form[data-controller*='inpaint-mask']"
  end

  test "create_inpaint rejects blank mask" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "completed")
    illustration.image.attach(io: StringIO.new("png"), filename: "source.png", content_type: "image/png")

    assert_no_enqueued_jobs do
      post inpaint_memo_illustration_path(illustration), params: { mask: "" }
    end

    assert_redirected_to inpaint_memo_illustration_path(illustration)
  end

  test "destroy_inpainted_image removes attachment" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "completed")
    illustration.image.attach(io: StringIO.new("png"), filename: "source.png", content_type: "image/png")
    illustration.inpainted_images.attach(
      io: StringIO.new("inpainted"),
      filename: "inpaint-1.png",
      content_type: "image/png",
      metadata: { sequence: 1 }
    )
    attachment = illustration.inpainted_image_attachments.first

    assert_difference -> { illustration.inpainted_images.attachments.count }, -1 do
      delete inpainted_image_memo_illustration_path(illustration, attachment_id: attachment.id)
    end

    assert_redirected_to memo_illustration_path(illustration)
    follow_redirect!
    assert_match "修正版 1 を削除しました", response.body
  end

  test "destroy_inpainted_image rejects in progress illustration" do
    illustration = MemoIllustration.create!(body: "サッカーボール", status: "inpainting")
    illustration.image.attach(io: StringIO.new("png"), filename: "source.png", content_type: "image/png")
    illustration.inpainted_images.attach(
      io: StringIO.new("inpainted"),
      filename: "inpaint-1.png",
      content_type: "image/png"
    )
    attachment = illustration.inpainted_image_attachments.first

    assert_no_difference -> { illustration.inpainted_images.attachments.count } do
      delete inpainted_image_memo_illustration_path(illustration, attachment_id: attachment.id)
    end

    assert_redirected_to memo_illustration_path(illustration)
  end
end
