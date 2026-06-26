ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

ORIGINAL_EMBEDDING_CLIENT_EMBED = EmbeddingClient.instance_method(:embed)

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    fixtures :all

    setup do
      EmbeddingClient.define_method(:embed) do |input:|
        text = Array(input).first.to_s
        seed = text.bytes.sum + text.length
        Array.new(Rails.application.config.x.nyoy.embedding_dimensions) do |index|
          Math.sin(seed + index)
        end
      end
    end
  end
end
