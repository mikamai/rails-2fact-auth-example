class AddDeviseTwoFactorToAdminUsers < ActiveRecord::Migration
  def change
    add_column :admin_users, :encrypted_otp_secret, :string
    add_column :admin_users, :encrypted_otp_secret_iv, :string
    add_column :admin_users, :encrypted_otp_secret_salt, :string
    add_column :admin_users, :consumed_timestep, :integer
    add_column :admin_users, :otp_required_for_login, :boolean
    # for otp secret:
    add_column :admin_users, :unconfirmed_otp_secret, :string
  end
end
