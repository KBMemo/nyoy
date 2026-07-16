# frozen_string_literal: true

module AgentGraph
  class UserTurnResolver
    def self.call(chat:, explicit_content:, required_label:)
      new(
        chat: chat,
        explicit_content: explicit_content,
        required_label: required_label
      ).call
    end

    def initialize(chat:, explicit_content:, required_label:)
      @chat = chat
      @explicit_content = explicit_content.to_s.strip.presence
      @required_label = required_label
    end

    def call
      content = @explicit_content.presence || latest_user_content
      raise ArgumentError, "#{@required_label} required" if content.blank?

      append_explicit_content! if @explicit_content.present? && latest_user_content != @explicit_content

      content
    end

    private

    def latest_user_content
      @chat.messages.where(role: :user).order(:id).last&.content.to_s.strip
    end

    def append_explicit_content!
      Message.suppressing_turbo_broadcasts do
        @chat.messages.create!(role: :user, content: @explicit_content)
      end
    end
  end
end
