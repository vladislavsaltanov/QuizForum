class AddJuryToAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :attempts, :jury_label, :string
    add_column :attempts, :jury_score, :float
    add_column :attempts, :jury_needs_review, :boolean
    add_column :attempts, :jury_reasons, :text
  end
end
