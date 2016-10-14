require 'spec_helper'
require 'breakers/dashboard'
require 'capybara/rspec'
require 'capybara/poltergeist'
require 'rack/test'

Capybara.javascript_driver = :poltergeist

describe Breakers::Dashboard, :integration, type: :feature, js: true do
  before(:all) do
    service = Breakers::Service.new(
      name: 'facebook',
      request_matcher: proc { |request_env| request_env.url.host =~ /.*facebook.com/ },
      seconds_before_retry: 60,
      error_threshold: 50
    )
    client = Breakers::Client.new(redis_connection: Redis.new, services: [service], logger: Logger.new(STDOUT))
    Breakers.set_client(client)
    Capybara.app = Breakers::Dashboard.new
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
