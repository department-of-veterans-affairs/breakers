require 'spec_helper'
require 'circuit_breaker/dashboard'
require 'capybara/rspec'
require 'capybara/poltergeist'
require 'rack/test'

Capybara.javascript_driver = :poltergeist

describe CircuitBreaker::Dashboard, :integration, type: :feature, js: true do
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

  it 'shows the services' do
    visit '/'
    expect(page).to have_content('facebook')
  end

  it 'can visit the requests page' do
    visit '/requests'
    expect(page).to have_content('facebook')
  end
end
