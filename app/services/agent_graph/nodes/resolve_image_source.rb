# frozen_string_literal: true

module AgentGraph
  module Nodes
    class ResolveImageSource
      def call(state:, run:, chat:)
        source = resolve_source(state, chat)
        return source if source.is_a?(AgentGraph::NodeResult)

        AgentGraph::NodeResult.next(updates: { "image_source" => source })
      end

      private

      def resolve_source(state, chat)
        tsuzura_media_id = state.dig("plan", "tsuzura_media_id").to_s.presence
        return resolve_tsuzura_media(tsuzura_media_id) if tsuzura_media_id

        message = resolve_message(state, chat)
        return fail_result(state, "解析する画像がありません。ユーザーが画像を添付してください。") unless message

        attachments = message.attachments.order(:id).to_a
        index = state.dig("plan", "attachment_index").to_i
        attachment = attachments[index]
        return fail_result(state, "指定された画像添付が見つかりません。") unless attachment

        {
          "kind" => "chat_attachment",
          "message_id" => message.id,
          "attachment_id" => attachment.id,
          "attachment_index" => index,
          "filename" => attachment.filename.to_s,
          "content_type" => attachment.content_type,
          "byte_size" => attachment.byte_size,
          "tsuzura_media_id" => attachment.metadata["tsuzura_media_id"]
        }.compact
      end

      def resolve_tsuzura_media(tsuzura_media_id)
        {
          "kind" => "tsuzura_media",
          "tsuzura_media_id" => tsuzura_media_id
        }
      end

      def resolve_message(state, chat)
        message_id = state.dig("plan", "message_id")
        return chat.messages.where(role: :user).find_by(id: message_id) if message_id.present?

        chat.messages.where(role: :user).order(:id).last
      end

      def fail_result(state, message)
        AgentGraph::NodeResult.fail(
          message,
          updates: {
            "errors" => Array(state["errors"]) + [ {
              "node" => "resolve_image_source",
              "code" => "IMAGE_SOURCE_MISSING",
              "message" => message
            } ]
          }
        )
      end
    end
  end
end
