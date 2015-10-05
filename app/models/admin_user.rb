class AdminUser < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :registerable,
         :recoverable, :rememberable, :trackable, :validatable,
         # 2 factor auth:
         :two_factor_authenticatable,
         :otp_secret_encryption_key => ENV['TWO_FACTOR_KEY']


  def activate_two_factor params
    otp_params = { otp_secret: unconfirmed_otp_secret }
    if !valid_password?(params[:password])
      errors.add :password, :invalid
      false
    elsif !validate_and_consume_otp!(params[:otp_attempt], otp_params)
      errors.add :otp_attempt, :invalid
      false
    else
      activate_two_factor
    end
  end

  def deactivate_two_factor params
    if !valid_password?(params[:password])
      errors.add :password, :invalid
      false
    else
      self.otp_required_for_login = false
      self.otp_secret = nil
      save
    end
  end

  private

  def activate_two_factor
    self.otp_required_for_login = true
    self.otp_secret = current_admin_user.unconfirmed_otp_secret
    self.unconfirmed_otp_secret = nil
    save
  end


end