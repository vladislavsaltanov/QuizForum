class CreateQuestionTrustees < ActiveRecord::Migration[8.1]
  def change
    create_table :question_trustees do |t|
      t.references :question, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :question_trustees, [ :question_id, :user_id ], unique: true
  end
end
