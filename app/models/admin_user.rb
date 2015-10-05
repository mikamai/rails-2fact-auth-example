class AdminUser < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         # 2 factor auth:
         :two_factor_authenticatable,
         :otp_secret_encryption_key => ENV['TWO_FACTOR_KEY']

end