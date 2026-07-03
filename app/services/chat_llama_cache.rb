# frozen_string_literal: true

# Pins each Chat to a llama.cpp slot and enables prompt KV cache reuse.
# History is still sent (API contract), but matching prefixes are not re-processed.
#
# Slot count is read from GET /props (total_slots). LLAMA_SLOT_COUNT is an optional fallback.
module ChatLlamaCache
  PROPS_CACHE_TTL = 60
  PROPS_ERROR_TTL = 10

  module_function

  def apply!(llm_chat, chat:)
    return llm_chat unless enabled?(chat)

    params = {}
    params[:cache_prompt] = true if cache_prompt?
    slot_id = slot_id_for(chat)
    params[:id_slot] = slot_id unless slot_id.nil?
    return llm_chat if params.empty?

    llm_chat.with_params(**params)
  end

  def enabled?(chat = nil)
    cache_prompt? || slot_count_for(chat).to_i.positive?
  end

  def cache_prompt?
    Rails.application.config.x.nyoy.llama_cache_prompt
  end

  def slot_id_for(chat)
    count = slot_count_for(chat)
    return nil if count.to_i <= 0
    return nil unless chat&.id

    chat.id.to_i % count
  end

  def slot_count_for(chat)
    base_url = api_base_for(chat)
    fetched = total_slots_from_props(base_url)
    return fetched if fetched.to_i.positive?

    fallback_slot_count
  end

  def fallback_slot_count
    count = Rails.application.config.x.nyoy.llama_slot_count.to_i
    count.positive? ? count : nil
  end

  def api_base_for(chat)
    model = chat&.model_association
    connection_key = model&.metadata&.dig("connection_key")
    if connection_key.present?
      NyoyConnectionStore.url(connection_key).to_s.sub(%r{/\z}, "").presence
    else
      model&.metadata&.dig("api_base").to_s.sub(%r{/\z}, "").presence
    end
  end

  def total_slots_from_props(base_url)
    return nil if base_url.blank?

    cache = props_cache
    entry = cache[base_url]
    return entry[:slots] if entry && entry[:expires_at] > Process.clock_gettime(Process::CLOCK_MONOTONIC)

    slots = LlamaCppClient.new(base_url: base_url).total_slots
    cache[base_url] = {
      slots: slots,
      expires_at: Process.clock_gettime(Process::CLOCK_MONOTONIC) + PROPS_CACHE_TTL
    }
    slots
  rescue LlamaCppClient::Error => e
    Rails.logger.warn("ChatLlamaCache: /props failed for #{base_url}: #{e.message}")
    cache[base_url] = {
      slots: nil,
      expires_at: Process.clock_gettime(Process::CLOCK_MONOTONIC) + PROPS_ERROR_TTL
    }
    nil
  end

  def clear_props_cache!
    props_cache.clear
  end

  def props_cache
    @props_cache ||= {}
  end
end
