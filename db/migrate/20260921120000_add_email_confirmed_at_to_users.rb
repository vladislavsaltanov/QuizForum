class AddEmailConfirmedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_confirmed_at, :datetime
    reversible do |dir|
      dir.up do
        User.reset_column_information
        # OAuth-аккаунты уже проверены провайдером — считаем подтверждёнными.
        User.where.not(provider: nil).update_all(email_confirmed_at: Time.current)
      end
    end
  end
end
