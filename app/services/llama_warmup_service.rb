# frozen_string_literal: true

# Keeps chat llama.cpp backends resident and CUDA/graph warm during idle
# periods, so the first user request after idle does not pay the cold-start
# penalty (model load + graph warmup) observed as a ~2x slower first turn.
#
# It intentionally skips warming while chats are active: an active backend is
# already warm, and a warmup request could evict a live conversation's slot KV
# cache. During genuine idle it pings each backend with a 1-token completion.
module LlamaWarmupService
  WARM_PROMPT = "ping"

  module_function

  def call(now: Time.current)
    return [] unless enabled?
    return [] if recently_active?(now: now)

    backends.map { |backend| warm(backend) }
  end

  def enabled?
    Rails.application.config.x.nyoy.llama_warmup_enabled
  end

  # Unique { base_url:, model: } for each enabled chat backend.
  def backends
    ChatModelCatalog.definitions.filter_map do |definition|
      base_url = resolve_base_url(definition)
      next if base_url.blank? || definition.model_id.blank?

      { base_url: base_url.sub(%r{/\z}, ""), model: definition.model_id }
    end.uniq
  end

  def recently_active?(now: Time.current)
    window = skip_recent_seconds
    return false if window <= 0

    Message.where(role: %w[user assistant])
           .where(created_at: (now - window)..)
           .exists?
  end

  def warm(backend)
    LlamaCppClient.new(base_url: backend[:base_url], model: backend[:model]).chat(
      messages: [{ role: "user", content: WARM_PROMPT }],
      temperature: 0,
      max_tokens: 1,
      read_timeout: read_timeout
    )
    Rails.logger.info("LlamaWarmupService: warmed #{backend[:model]} @ #{backend[:base_url]}")
    true
  rescue LlamaCppClient::Error => e
    Rails.logger.warn("LlamaWarmupService: failed to warm #{backend[:base_url]}: #{e.message}")
    false
  end

  def resolve_base_url(definition)
    if definition.connection_key.present?
      NyoyConnectionStore.url(definition.connection_key).presence || definition.api_base
    else
      definition.api_base
    end
  end

  def skip_recent_seconds
    Rails.application.config.x.nyoy.llama_warmup_skip_recent_seconds.to_i
  end

  def read_timeout
    Rails.application.config.x.nyoy.llama_warmup_read_timeout.to_i
  end
end
