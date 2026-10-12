class CommentsOnTests < ActiveRecord::Migration[8.0]
  def up
    add_reference :comments, :test, foreign_key: true
    change_column_null :comments, :question_id, true
  end

  def down
    Comment.where(question_id: nil).delete_all
    remove_reference :comments, :test, foreign_key: true
    change_column_null :comments, :question_id, false
  end
end
