# frozen_string_literal: true

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "admin" => "admin/dashboard#index"
  root "admin/dashboard#index"

  mount Api::V1::Base => "/"
end
