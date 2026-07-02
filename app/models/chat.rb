class Chat < ApplicationRecord
  acts_as_chat

  def assume_model_exists
    true
  end

  def to_llm
    self.context = ChatModelCatalog.context_for(model_association)
    @chat = nil
    llm = super
    ChatTools::Registry.apply!(llm)
    llm
  end
end
