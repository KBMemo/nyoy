# frozen_string_literal: true

module ChatTools
  class AnalyzeImage < RubyLLM::Tool
    description "ユーザーが Chat に添付した画像、または葛籠のメディア ID を vision LLM で解析する。画像の内容説明・文字読取・物体識別などに使う。"

    def initialize(chat:)
      @chat = chat
    end

    def name
      "analyze_image"
    end

    param :prompt, desc: "画像に対する質問や解析指示", required: true
    param :attachment_index, type: "integer", desc: "添付画像の番号（0 始まり。省略時は直近の画像）", required: false
    param :tsuzura_media_id, desc: "葛籠メディア ID（添付の代わりに指定。get_media で参照）", required: false

    def execute(prompt:, attachment_index: 0, tsuzura_media_id: nil)
      image_source = resolve_image_source(attachment_index: attachment_index, tsuzura_media_id: tsuzura_media_id)
      return image_source if image_source.is_a?(Hash) && image_source[:error]

      analysis = vision_service.analyze(
        image: image_source[:data],
        mime_type: image_source[:content_type],
        prompt: prompt
      )
      {
        analysis: analysis,
        filename: image_source[:filename],
        content_type: image_source[:content_type],
        tsuzura_media_id: image_source[:tsuzura_media_id]
      }.compact
    rescue TsuzuraClient::Error, VisionChatService::Error, LlamaCppClient::Error => e
      { error: e.message }
    end

    private

    def resolve_image_source(attachment_index:, tsuzura_media_id:)
      if tsuzura_media_id.present?
        return { error: "葛籠 API が未設定です" } unless Registry.media_tools_available?

        download = Registry.tsuzura_client.download_media(tsuzura_media_id)
        {
          data: download.data,
          content_type: download.content_type,
          filename: download.filename.presence || "#{tsuzura_media_id}.bin",
          tsuzura_media_id: tsuzura_media_id
        }
      else
        attachment = find_attachment(attachment_index)
        return { error: "解析する画像がありません。ユーザーが画像を添付しているか、tsuzura_media_id を指定してください。" } unless attachment

        {
          data: attachment.download,
          content_type: attachment.content_type,
          filename: attachment.filename.to_s,
          tsuzura_media_id: attachment.metadata["tsuzura_media_id"]
        }
      end
    end

    def find_attachment(index)
      attachments = ChatImageAttachments.recent_attachments(@chat)
      attachments[index.to_i]
    end

    def vision_service
      Registry.vision_service
    end
  end
end
