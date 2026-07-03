# frozen_string_literal: true

module ChatTools
  class AnalyzeImage < RubyLLM::Tool
    description "ユーザーが Chat に添付した画像を vision LLM で解析する。画像の内容説明・文字読取・物体識別などに使う。"

    def initialize(chat:)
      @chat = chat
    end

    def name
      "analyze_image"
    end

    param :prompt, desc: "画像に対する質問や解析指示", required: true
    param :attachment_index, type: "integer", desc: "添付画像の番号（0 始まり。省略時は直近の画像）", required: false

    def execute(prompt:, attachment_index: 0)
      attachment = find_attachment(attachment_index)
      return { error: "解析する画像がありません。ユーザーが画像を添付しているか確認してください。" } unless attachment

      analysis = vision_service.analyze(
        image: attachment.download,
        mime_type: attachment.content_type,
        prompt: prompt
      )
      {
        analysis: analysis,
        filename: attachment.filename.to_s,
        content_type: attachment.content_type
      }
    rescue VisionChatService::Error, LlamaCppClient::Error => e
      { error: e.message }
    end

    private

    def find_attachment(index)
      attachments = ChatImageAttachments.recent_attachments(@chat)
      attachments[index.to_i]
    end

    def vision_service
      Registry.vision_service
    end
  end
end
