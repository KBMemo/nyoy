# frozen_string_literal: true

module ChatContextLimiter
  module_function

  def trim(messages, max_turns:)
    return messages if max_turns.blank? || max_turns.to_i <= 0

    system_messages, others = messages.partition { |message| message.role.to_s == "system" }
    kept = turns(others).last(max_turns.to_i).flatten

    system_messages + kept
  end

  def turns(messages)
    messages.each_with_object([]) do |message, grouped|
      if message.role.to_s == "user" && grouped.last&.any?
        grouped << []
      end

      grouped << [] if grouped.empty?
      grouped.last << message
    end
  end

  module_function :turns
end
