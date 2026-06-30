# frozen_string_literal: true

class RemoveImg2imgFromMemoIllustrations < ActiveRecord::Migration[8.0]
  def change
    remove_column :memo_illustrations, :denoising_strength, :float
  end
end
