# frozen_string_literal: true

module Contracts
  class ApplicationContract < Dry::Validation::Contract
    config.messages.backend = :yaml
  end
end
