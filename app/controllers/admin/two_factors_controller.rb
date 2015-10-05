class Admin::TwoFactorsController < ApplicationController
  before_filter :authenticate_admin_user!

  # If user has already enabled the two-factor auth, we generate a
  #   temp. otp_secret and show the 'new' template.
  # Otherwise we show the 'show' template which will allow the user to disable
  #   the two-factor auth
  def show
    unless current_admin_user.otp_required_for_login?
      current_admin_user.unconfirmed_otp_secret = AdminUser.generate_otp_secret
      current_admin_user.save!
      @qr = RQRCode::QRCode.new(two_factor_otp_url).to_img.resize(240, 240).to_data_url
      render 'new'
    end
  end

  # AdminUser#activate_two_factor will return a boolean. When false is returned
  #   we presume the model has some errors.
  def create
    permitted_params = params.require(:admin_user).permit :password, :otp_attempt
    if current_admin_user.activate_two_factor permitted_params
      redirect_to root_path, notice: "You have enabled Two Factor Auth"
    else
      render 'new'
    end
  end

  # If the provided password is correct, two-factor is disabled
  def destroy
    permitted_params = params.require(:admin_user).permit :password
    if current_admin_user.deactivate_two_factor permitted_params
      redirect_to root_path, notice: "You have disabled Two Factor Auth"
    else
      render 'show'
    end
  end

  private

  # The url needed to generate the QRCode so it can be acquired by
  #   Google Authenticator
  def two_factor_otp_url
    "otpauth://totp/%{app_id}?secret=%{secret}&issuer=%{app}" % {
      :secret => current_admin_user.unconfirmed_otp_secret,
      :app    => "your-app",
      :app_id => "YourApp"
    }
  end
end