# frozen_string_literal: true

module AgentGraph
  class GraphDefinition
    attr_reader :name, :start_node, :state_schema

    def initialize(name:, start_node:, nodes:, edges:, state_schema: nil)
      @name = name.to_s
      @start_node = start_node.to_s
      @nodes = nodes.stringify_keys.freeze
      @edges = edges.stringify_keys.freeze
      @state_schema = state_schema
    end

    def node_for(name)
      @nodes[name.to_s]
    end

    def next_node_for(name, state)
      edge = @edges[name.to_s]
      raise "missing edge for node: #{name}" unless edge

      edge.next_node(state)
    end
  end
end
