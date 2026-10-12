class TestQuestionCombos < ActiveRecord::Migration[8.0]
  def up
    add_reference :questions, :test, foreign_key: true
    add_column :questions, :points, :integer, default: 1, null: false
    add_column :questions, :position, :integer, default: 0, null: false

    drop_table :test_attempts
    drop_table :test_tasks
  end

  def down
    create_table :test_tasks do |t|
      t.bigint :test_id, null: false
      t.text :body, default: "", null: false
      t.string :answer_type, default: "text", null: false
      t.jsonb :options, default: [], null: false
      t.integer :points, default: 1, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
      t.index [ :test_id ], name: "index_test_tasks_on_test_id"
    end
    create_table :test_attempts do |t|
      t.bigint :test_task_id, null: false
      t.bigint :user_id, null: false
      t.text :body
      t.jsonb :selected, default: [], null: false
      t.string :verdict, default: "pending", null: false
      t.timestamps
      t.index [ :test_task_id, :user_id ], name: "index_test_attempts_on_test_task_id_and_user_id", unique: true
      t.index [ :test_task_id ], name: "index_test_attempts_on_test_task_id"
      t.index [ :user_id ], name: "index_test_attempts_on_user_id"
    end

    remove_reference :questions, :test, foreign_key: true
    remove_column :questions, :points
    remove_column :questions, :position
  end
end
