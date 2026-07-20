# frozen_string_literal: true

# Pins each Chat to a llama.cpp slot and enables prompt KV cache reuse.
# History is still sent (API contract), but matching prefixes are not re-processed.
#
# Slot count is read from GET /props (total_slots). LLAMA_SLOT_COUNT is an optional fallback.
require "zlib"

module ChatLlamaCache
  PROPS_CACHE_TTL = 60
  PROPS_ERROR_TTL = 10

  module_function

  def apply!(llm_chat, chat:, model: nil, slot_key: nil)
    metadata = metadata_for(chat, model: model, slot_key: slot_key)
    llm_chat.instance_variable_set(:@nyoy_llama_cache_metadata, metadata)
    return llm_chat unless metadata[:enabled]

    existing = llm_chat.instance_variable_get(:@params) || {}
    params = {}
    params[:cache_prompt] = true if metadata[:cache_prompt]
    params[:id_slot] = metadata[:slot_id] unless metadata[:slot_id].nil?
    params[:stream_options] = stream_options_with_usage(existing)
    return llm_chat if params.empty?

    llm_chat.with_params(**existing.merge(params))
  end

  def metadata_for(chat, model: nil, slot_key: nil)
    model ||= chat&.model_association
    return disabled_metadata if openai_model?(model)

    count = slot_count_for(chat, model: model)
    slot_id = slot_id_for(chat, model: model, slot_key: slot_key)
    enabled = cache_prompt? || count.to_i.positive?

    {
      enabled: enabled,
      cache_prompt: cache_prompt?,
      slot_id: slot_id,
      slot_count: count,
      slot_pool: slot_pool_for(count, slot_key),
      auxiliary_slot_count: auxiliary_slot_count(count)
    }
  end

  def enabled?(chat = nil)
    return false if openai_model?(chat&.model_association)

    cache_prompt? || slot_count_for(chat).to_i.positive?
  end

  def openai_chat?(chat)
    openai_model?(chat&.model_association)
  end

  def openai_model?(model)
    model&.metadata&.dig("connection_key") == "openai"
  end

  def disabled_metadata
    {
      enabled: false,
      cache_prompt: false,
      slot_id: nil,
      slot_count: nil,
      slot_pool: nil,
      auxiliary_slot_count: nil
    }
  end

  def cache_prompt?
    Rails.application.config.x.nyoy.llama_cache_prompt
  end

  def slot_id_for(chat, model: nil, slot_key: nil)
    count = slot_count_for(chat, model: model)
    return nil if count.to_i <= 0

    reserved = auxiliary_slot_count(count)
    if slot_key.present?
      return Zlib.crc32(slot_key.to_s) % count if reserved.zero?

      return count - reserved + (Zlib.crc32(slot_key.to_s) % reserved)
    end
    return nil unless chat&.id

    chat.id.to_i % (count - reserved)
  end

  def auxiliary_slot_count(total_slots)
    total = total_slots.to_i
    return 0 if total <= 1

    configured = Rails.application.config.x.nyoy.llama_aux_slot_count.to_i
    configured.clamp(0, total - 1)
  end

  def slot_pool_for(total_slots, slot_key)
    return "chat" if slot_key.blank?

    auxiliary_slot_count(total_slots).positive? ? "auxiliary" : "shared"
  end

  def slot_count_for(chat, model: nil)
    base_url = api_base_for(chat, model: model)
    fetched = total_slots_from_props(base_url)
    return fetched if fetched.to_i.positive?

    fallback_slot_count
  end

  def fallback_slot_count
    count = Rails.application.config.x.nyoy.llama_slot_count.to_i
    count.positive? ? count : nil
  end

  def api_base_for(chat, model: nil)
    model ||= chat&.model_association
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

  def stream_options_with_usage(existing)
    options = existing[:stream_options] || existing["stream_options"] || {}
    options.to_h.deep_symbolize_keys.merge(include_usage: true)
  end
end
