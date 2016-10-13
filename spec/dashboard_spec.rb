require 'spec_helper'
require 'circuit_breaker/dashboard'
require 'capybara/rspec'
require 'capybara/poltergeist'
require 'rack/test'

Capybara.javascript_driver = :poltergeist

describe CircuitBreaker::Dashboard, :integration, type: :feature do
  before(:all) do
    service = CircuitBreaker::Service.new(
      name: 'facebook',
      host: /.*facebook.com/,
      path: /.*/
    )
    client = CircuitBreaker::Client.new(redis_connection: Redis.new, services: [service], logger: Logger.new(STDOUT))
    Capybara.app = CircuitBreaker::Dashboard.new(client)
  end

  it 'can visit the main page' do
    visit '/'
    expect(page).to have_content('Dashboard')
  end
end
