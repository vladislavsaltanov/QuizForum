class CreateTestAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :test_attempts do |t|
      t.references :test_task, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body
      t.jsonb :selected, default: [], null: false
      t.string :verdict, default: "pending", null: false

      t.timestamps
    end
    add_index :test_attempts, [ :test_task_id, :user_id ], unique: true
  end
end
