class AddCodeCheckFields < ActiveRecord::Migration[8.1]
  def change
    add_column :questions, :code_languages, :string, array: true, default: [], null: false
    add_column :questions, :reference_language, :string
    add_column :attempts, :code_passed, :integer
    add_column :attempts, :code_total, :integer
    add_column :attempts, :code_needs_review, :boolean
    add_column :attempts, :code_reasons, :text
  end
end
