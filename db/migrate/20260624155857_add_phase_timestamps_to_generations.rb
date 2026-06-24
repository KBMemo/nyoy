class AddPhaseTimestampsToGenerations < ActiveRecord::Migration[8.1]
  def change
    %i[image_generations memo_illustrations].each do |table|
      change_table table, bulk: true do |t|
        t.datetime :prompt_started_at
        t.datetime :prompt_finished_at
        t.datetime :image_started_at
        t.datetime :image_finished_at
      end
    end
  end
end
