class AddExampleFieldsToQuestions < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :example_input, :text
    add_column :questions, :example_output, :text
  end
end
