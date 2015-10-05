# Add Two Factor Authentication to your Rails app

Recently we started adding two-factor auth to all our apps by default. And obviously there is a gem for this: [devise-two-factor](https://github.com/tinfoil/devise-two-factor/)


### Setup

This tutorial builds on an existing rails application using devise for authentication, so please follow the devise readme before continuing. We're going to use `AdminUser` model, of course you can use whatever model name you prefer, for example you may want to stick to a more general `User` model.
You can find the complete final code for this article on [github](https://github.com/mikamai/rails-2fact-auth-example)

Add to your `Gemfile`:

```ruby
gem 'devise-two-factor' # for two factor
gem 'rqrcode_png' # for qr codes
```

Then, run `bundle` to install them.

Now we need to tell the user model to use the two-factor, and we need also to add some database columns to store the secret code for authenticating the [OTP](https://en.wikipedia.org/wiki/One-time_password) password. The gem offers a generator in order to generate these colums. Run `rails generate devise_two_factor AdminUser TWO_FACTOR_SECRET_KEY_NAME`, where `AdminUser` is the name of the model you wish to add two-factor auth to, and `TWO_FACTOR_SECRET` is the ENV variable name for your two factor encryption key (the variable must be a random sequence of characters, similar to the `SECRET_KEY_BASE` env variable). Remember, `git diff` is your friend when you need to check what generators did to your application code.

When the generation is complete you should see a new migration, like the following (`admin_users` will be replaced with your model table name):

```ruby
class AddDeviseTwoFactorToAdminUsers < ActiveRecord::Migration
  def change
    add_column :admin_users, :encrypted_otp_secret,      :string
    add_column :admin_users, :encrypted_otp_secret_iv,   :string
    add_column :admin_users, :encrypted_otp_secret_salt, :string
    add_column :admin_users, :otp_required_for_login,    :boolean
    add_column :admin_users, :consumed_timestep,         :integer
  end
end
```

Edit the migration and add another column: this one will store a temporary `otp_secret` during the two-factor activation process (which we'll see later):

```ruby
add_column :admin_users, :unconfirmed_otp_secret, :string
```

Now, check your model (`AdminUser` in my case): you should see that the devise configuration `database_authenticatable` has been replaced with `two_factor_authenticatable`:

```
class AdminUser < ActiveRecord::Base
  devise :rememberable, :trackable, :lockable,
         :session_limitable, :two_factor_authenticatable,
         :otp_secret_encryption_key => ENV['TWO_FACTOR_SECRET']
```

Run `rake db:migrate` and the setup is complete.


### Authentication

If you haven't done it already, run `rails generate devise:views` to copy all devise views inside your application.

Open `app/views/devise/sessions/new.html.erb` and add a new field called `otp_attempt`. You should obtain something like:

```html
<h2>Log in</h2>

<%= form_for(resource, as: resource_name, url: session_path(resource_name)) do |f| %>
  <div class="field">
    <%= f.label :email %><br />
    <%= f.email_field :email, autofocus: true %>
  </div>

  <div class="field">
    <%= f.label :password %><br />
    <%= f.password_field :password, autocomplete: "off" %>
  </div>

  <div class="field">
    <%= f.label :otp_attempt %><br />
    <%= f.text_field :otp_attempt, autocomplete: "off" %>
  </div>

  <% if devise_mapping.rememberable? -%>
    <div class="field">
      <%= f.check_box :remember_me %>
      <%= f.label :remember_me %>
    </div>
  <% end -%>

  <div class="actions">
    <%= f.submit "Log in" %>
  </div>
<% end %>

<%= render "devise/shared/links" %>
```

Then, open `app/controllers/application_controller.rb` to permit a new login parameter for our model:

```
before_action :configure_permitted_parameters, if: :devise_controller?

protected

def configure_permitted_parameters
  devise_parameter_sanitizer.for(:sign_in) << :otp_attempt
end
```

Ok, authentication is ready. But there is no way to activate the two factor auth, for now.


### Two Factor Activation

It's time for the controller and views. Add the following to your authentication model (`AdminUser` in my case), in order to ease the controller activate/deactivate actions:

```ruby
def activate_two_factor params
  otp_params = { otp_secret: unconfirmed_otp_secret }
  if !valid_password?(params[:password])
    errors.add :password, :invalid
    false
  elsif !validate_and_consume_otp!(params[:otp_attempt], otp_params)
    errors.add :otp_attempt, :invalid
    false
  else
    activate_two_factor!
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

def activate_two_factor!
  self.otp_required_for_login = true
  self.otp_secret = current_admin_user.unconfirmed_otp_secret
  self.unconfirmed_otp_secret = nil
  save
end
```

So, when this method is called, `params` is required to contain the user password and the otp attempt. If they are both valid the method will activate the two factor authentication.

We'll have the following routes:

```ruby
namespace :admin do
  get    '/two_factor' => 'two_factors#show', as: 'admin_two_factor'
  post   '/two_factor' => 'two_factors#create'
  delete '/two_factor' => 'two_factors#destroy'
end
```

Now, the two factors controller (read the comments):

```ruby
class Admin::TwoFactorsController < ApplicationController
  before_filter :authenticate_admin_user!

  def new
  end

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
```

Finally, the views:

- __app/views/admin/two_factors/new.html.erb__

```html
<div class="page-header"><h2>Enable Two Factor Auth</h2></div>

<p>To enable <em>Two Factor Auth</em>, scan the following QR Code:</p>

<p class="text-center"><%= image_tag @qr %></p>

<p>Then, verify that the pairing was successful by entering your password and a code below.</p>

<%= form_for current_admin_user, url: [:admin, :two_factor], method: 'POST' do |f| %>
  <div class="field">
    <%= f.label :password %><br />
    <%= f.password_field :password, autocomplete: "off" %>
  </div>

  <div class="field">
    <%= f.label :otp_attempt %><br />
    <%= f.text_field :otp_attempt, autocomplete: "off" %>
  </div>

  <div class="actions">
    <%= f.submit "Enable" %>
  </div>
<% end %>
```

- __app/views/admin/two_factors/show.html.erb__

```html
<div class="page-header"><h2>Disable Two Factor Auth</h2></div>

<p>Type your password to disable <em>Two Factor Auth</em></p>

<%= form_for current_admin_user, url: [:admin, :two_factor], method: 'DELETE' do |f| %>
  <div class="field">
    <%= f.label :password %><br />
    <%= f.password_field :password, autocomplete: "off" %>
  </div>

  <div class="actions">
    <%= f.submit "Disable" %>
  </div>
<% end %>
```

So, if a logged user visits `/admin/two_factor` and he has no two-factor auth enabled, he will see the `new` template. Filling the form will activate the two factor auth.

Once the user has two-factor auth enabled, visiting `/admin/two_factor` will render the `show` template. He can fill the form with his password to disable the two factor auth.


### Improvements

There's no space left here for other words, but you can change the 'show' action to always render a template where a user can:

- activate __or reconfigure__ the two factor
- disable the two factor if it's enabled

You can also add the backup codes, using the [TwoFactorBackuppable](https://github.com/tinfoil/devise-two-factor#backup-codes) strategy.


### Issues

If you use Docker, you'll surely encounter a problem. During the `assets:precompile` the app will try to connect to the DB. [I've opened an issue](https://github.com/tinfoil/devise-two-factor/issues/47) but haven't received yet a reply until now.

A workaround I found is to ignore devise routes during the `assets:precompile`. Create the file `config/initializers/precompile.rb`:

```ruby
# used in config/routes.rb to ignore some routes. See https://github.com/tinfoil/devise-two-factor/issues/47 for details
module Precompile
  # Public: ignore the following block during rake assets:precompile
  def self.ignore
    unless ARGV.any? { |e| e == 'assets:precompile' }
      yield
    else
      line = caller.first
      puts "Ignoring line '#{line}' during precompile"
    end
  end
end
```

And wrap your devise routes inside `Precompile.ignore` like in the following example:

```ruby
Precompile.ignore do
  devise_for :admin_users, path: 'admin/admin_users'
end
```

This way when the routes file is parsed during the `assets:precompile` task, it will not load the AdminUser model that are generating a connection attempt on the DB.
