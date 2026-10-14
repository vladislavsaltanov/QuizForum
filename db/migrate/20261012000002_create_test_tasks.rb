class CreateTestTasks < ActiveRecord::Migration[8.0]
  def change
    create_table :test_tasks do |t|
      t.references :test, null: false, foreign_key: true
      t.integer :position, default: 0, null: false
      t.text :body, default: "", null: false
      t.string :answer_type, default: "text", null: false
      t.jsonb :options, default: [], null: false
      t.integer :points, default: 1, null: false

      t.timestamps
    end
  end
end
