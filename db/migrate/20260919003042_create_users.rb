class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :display_role
      t.string :provider
      t.string :uid

      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, [ :provider, :uid ], unique: true
  end
end
