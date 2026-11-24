# frozen_string_literal: true

module Api
  module V1
    class Base < Grape::API
      version "v1", using: :path
      format :json
      prefix :api

      rescue_from Grape::Exceptions::ValidationErrors do |e|
        error!({ error: "bad_request", details: e.message }, 400)
      end

      mount Api::V1::PaymentsApi
      mount Api::V1::MerchantsApi
      mount Api::V1::WebhooksApi
      mount Api::V1::AdminApi

      get :health do
        ActiveRecord::Base.connection.execute("SELECT 1")
        { status: "ok", db: "connected", timestamp: Time.current.iso8601 }
      end
    end
  end
end
