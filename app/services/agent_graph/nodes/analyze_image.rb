# frozen_string_literal: true

module AgentGraph
  module Nodes
    class AnalyzeImage
      def call(state:, run:, chat:)
        image_source = state["image_source"] || {}
        payload = image_payload(image_source, chat)
        return payload if payload.is_a?(AgentGraph::NodeResult)
        return unsupported_content_type(state, payload[:content_type]) unless supported_content_type?(payload[:content_type])

        result = AgentGraph::RoleServices.fetch(:vision).call(
          image: payload.fetch(:data),
          mime_type: payload.fetch(:content_type),
          prompt: state.fetch("question").to_s,
          state: state,
          run: run,
          chat: chat
        )
        analysis, metadata = result.is_a?(Array) ? result : [ result, {} ]
        metadata = metadata.to_h.stringify_keys

        AgentGraph::NodeResult.next(
          updates: {
            "analysis" => analysis,
            "analysis_meta" => metadata.merge(
              "source" => image_source["kind"],
              "filename" => payload[:filename],
              "content_type" => payload[:content_type],
              "role" => "vision",
              "profile" => AgentGraph::RoleServices.active_profile_for(:vision).to_s
            ).compact
          }
        )
      rescue TsuzuraClient::Error, VisionChatService::Error, LlamaCppClient::Error => e
        AgentGraph::NodeResult.fail(
          e.message,
          updates: {
            "errors" => Array(state["errors"]) + [ {
              "node" => "analyze_image",
              "code" => "VISION_ANALYSIS_FAILED",
              "message" => e.message
            } ]
          }
        )
      end

      private

      def image_payload(image_source, chat)
        case image_source["kind"]
        when "chat_attachment"
          attachment_payload(image_source, chat)
        when "tsuzura_media"
          tsuzura_payload(image_source)
        else
          AgentGraph::NodeResult.fail("画像ソースが未解決です。")
        end
      end

      def supported_content_type?(content_type)
        ChatImageAttachments::ALLOWED_CONTENT_TYPES.include?(content_type.to_s)
      end

      def unsupported_content_type(state, content_type)
        message = "対応していない画像形式です: #{content_type.presence || "unknown"}"
        AgentGraph::NodeResult.fail(
          message,
          updates: {
            "errors" => Array(state["errors"]) + [ {
              "node" => "analyze_image",
              "code" => "UNSUPPORTED_IMAGE_CONTENT_TYPE",
              "message" => message
            } ]
          }
        )
      end

      def attachment_payload(image_source, chat)
        attachment = ActiveStorage::Attachment.find_by(id: image_source["attachment_id"])
        return AgentGraph::NodeResult.fail("画像添付が見つかりません。") unless attachment
        unless attachment.record == chat.messages.find_by(id: image_source["message_id"])
          return AgentGraph::NodeResult.fail("画像添付が別の Chat に属しています。")
        end

        {
          data: attachment.download,
          content_type: attachment.content_type,
          filename: attachment.filename.to_s
        }
      end

      def tsuzura_payload(image_source)
        return AgentGraph::NodeResult.fail("葛籠 API が未設定です") unless ChatTools::Registry.media_tools_available?

        download = ChatTools::Registry.tsuzura_client.download_media(image_source.fetch("tsuzura_media_id"))
        {
          data: download.data,
          content_type: download.content_type,
          filename: download.filename
        }
      end
    end
  end
end
