class AddPublishedToTests < ActiveRecord::Migration[8.0]
  def up
    add_column :tests, :published, :boolean, default: false, null: false
    Test.reset_column_information
    Test.update_all(published: true)
  end

  def down
    remove_column :tests, :published
  end
end
