class AddAiFieldsToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :ai_generated, :boolean, default: false, null: false
    add_column :questions, :ai_batch, :date
    # Idempotency lookup: one batch per day, at most 9 rows sharing it.
    add_index :questions, :ai_batch, where: "ai_generated", name: "index_questions_on_ai_batch_ai_only"
  end
end
