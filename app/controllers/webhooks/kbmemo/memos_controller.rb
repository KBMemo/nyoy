# frozen_string_literal: true

module Webhooks
  module Kbmemo
    class MemosController < ActionController::API
      before_action :require_enabled!

      def create
        raw_body = request.raw_post
        verify_signature!(raw_body)
        payload = parse_payload(raw_body)
        event = find_or_create_event!(payload)

        if event.previously_new_record?
          MemoKnowledgeWebhookJob.perform_later(event.event_id)
          render json: { accepted: true, event_id: event.event_id }, status: :accepted
        else
          render json: { accepted: true, event_id: event.event_id, duplicate: true }
        end
      rescue MemoRagWebhookSignature::Error
        head :unauthorized
      rescue JSON::ParserError
        render json: { error: { code: "invalid_json", message: "JSON payload is invalid" } }, status: :unprocessable_entity
      rescue ActiveRecord::RecordInvalid => e
        render json: {
          error: {
            code: "validation_error",
            message: e.record.errors.full_messages.to_sentence
          }
        }, status: :unprocessable_entity
      rescue KeyError => e
        render json: {
          error: {
            code: "validation_error",
            message: "#{e.key} is required"
          }
        }, status: :unprocessable_entity
      end

      private

      def require_enabled!
        config = Rails.application.config.x.nyoy
        head :not_found unless config.memo_rag_webhook_enabled && config.memo_rag_webhook_secret.present?
      end

      def verify_signature!(raw_body)
        MemoRagWebhookSignature.verify!(
          raw_body: raw_body,
          timestamp: request.headers["X-KBMemo-Webhook-Timestamp"],
          signature: request.headers["X-KBMemo-Signature"]
        )
      end

      def parse_payload(raw_body)
        JSON.parse(raw_body)
      end

      def find_or_create_event!(payload)
        event_id = payload.fetch("event_id").to_s
        existing = MemoRagWebhookEvent.find_by(event_id: event_id)
        return existing if existing

        MemoRagWebhookEvent.create!(
          event_id: event_id,
          event_type: payload.fetch("event_type"),
          account_id: payload.fetch("account_id"),
          memo_uid: payload.fetch("memo_uid"),
          memo_id: payload["memo_id"],
          memo_updated_at: parse_time(payload["memo_updated_at"]),
          occurred_at: parse_time(payload.fetch("occurred_at"))
        )
      rescue ActiveRecord::RecordNotUnique
        MemoRagWebhookEvent.find_by!(event_id: event_id)
      end

      def parse_time(value)
        return nil if value.blank?

        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
