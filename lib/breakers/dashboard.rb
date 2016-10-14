require 'sinatra/base'
require 'json'

require 'byebug'

module Breakers
  class Dashboard < Sinatra::Base
    TWO_WEEKS = 60 * 60 * 24 * 14

    # Paths to assets
    dir = File.dirname(File.expand_path(__FILE__))
    set :views, "#{dir}/dashboard/views"
    set :public_folder, "#{dir}/dashboard/static"

    get '/' do
      erb :index, locals: { services: Breakers.client.services }
    end

    get '/outages' do
      erb :index, locals: { services: Breakers.client.services }
    end

    get '/requests' do
      erb :requests, locals: { services: Breakers.client.services }
    end

    get '/favicon.ico' do
    end

    get '/outages.json' do
      service = Breakers.client.service_for_uri_name(name: params[:service])
      if !service
        status 404
        { error: "Service #{params[:service]} not found" }.to_json
      else
        outages = service.outages_in_range(start_time: Time.now - TWO_WEEKS, end_time: Time.now)
        { service: service.uri_name, outages: outages }.to_json
      end
    end

    get '/requests.json' do
      service = Breakers.client.service_for_uri_name(name: params[:service])
      if !service
        status 404
        { error: "Service #{params[:service]} not found" }.to_json
      else
        successes = service.successes_in_range(start_time: Time.now - TWO_WEEKS, end_time: Time.now)
        errors = service.errors_in_range(start_time: Time.now - TWO_WEEKS, end_time: Time.now)
        { service: service.uri_name, successes: successes, errors: errors }.to_json
      end
    end
  end
end
