Rails.application.routes.draw do
  get 'home/index'
  root 'home#index'

  devise_for :admin_users

  namespace :admin do
    get    '/two_factor' => 'two_factors#show', as: 'admin_two_factor'
    post   '/two_factor' => 'two_factors#create'
    delete '/two_factor' => 'two_factors#destroy'
  end
end