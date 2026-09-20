class CreateQuestionBank < ActiveRecord::Migration[8.1]
  def change
    create_table :questions do |t|
      t.string :title, null: false
      t.text :body, null: false, default: ""
      t.string :answer_type, null: false, default: "text"
      t.jsonb :options, null: false, default: []
      t.text :reference_answer, null: false, default: ""
      t.datetime :deadline, null: false
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.string :tags, array: true, null: false, default: []
      t.timestamps
    end

    create_table :attempts do |t|
      t.references :question, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false, default: ""
      t.string :language
      t.jsonb :selected, null: false, default: []
      t.string :verdict, null: false, default: "pending"
      t.timestamps
      t.index %i[question_id user_id], unique: true
    end

    create_table :comments do |t|
      t.references :question, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    create_table :reports do |t|
      t.references :question, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
      t.index %i[question_id user_id], unique: true
    end
  end
end
