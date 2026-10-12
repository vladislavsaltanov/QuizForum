class CreateTests < ActiveRecord::Migration[8.0]
  def change
    create_table :tests do |t|
      t.string :title, null: false
      t.text :body, default: "", null: false
      t.datetime :deadline, null: false
      t.string :password_digest
      t.integer :max_points
      t.references :author, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
