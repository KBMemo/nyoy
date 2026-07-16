# frozen_string_literal: true

module AgentGraph
  class Edge
    def self.end
      new(end_node: true)
    end

    def initialize(to: nil, end_node: false)
      @to = to
      @end_node = end_node
    end

    def next_node(state)
      return nil if @end_node
      return @to.call(state) if @to.respond_to?(:call)

      @to
    end
  end
end
