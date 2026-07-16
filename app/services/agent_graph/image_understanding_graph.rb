# frozen_string_literal: true

module AgentGraph
  class ImageUnderstandingGraph < GraphDefinition
    NAME = "image_understanding"
    START = "plan_image_understanding"

    def initialize
      super(
        name: NAME,
        start_node: START,
        nodes: {
          "plan_image_understanding" => Nodes::PlanImageUnderstanding.new,
          "resolve_image_source" => Nodes::ResolveImageSource.new,
          "analyze_image" => Nodes::AnalyzeImage.new,
          "finalize_image_answer" => Nodes::FinalizeImageAnswer.new
        },
        edges: {
          "plan_image_understanding" => Edge.new(to: "resolve_image_source"),
          "resolve_image_source" => Edge.new(to: "analyze_image"),
          "analyze_image" => Edge.new(to: "finalize_image_answer"),
          "finalize_image_answer" => Edge.end
        },
        state_schema: ImageUnderstandingStateSchema
      )
    end
  end
end
