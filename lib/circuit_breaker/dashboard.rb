require 'sinatra/base'
require 'json'

require 'byebug'

module CircuitBreaker
  class Dashboard < Sinatra::Base
    TWO_WEEKS = 60 * 60 * 24 * 14

    # Paths to assets
    dir = File.dirname(File.expand_path(__FILE__))
    set :views, "#{dir}/dashboard/views"
    set :public_folder, "#{dir}/dashboard/static"

    def initialize(client)
      @client = client
      super
    end

    get '/' do
      erb :index, locals: { services: @client.services }
    end

    get '/outages' do
      erb :index, locals: { services: @client.services }
    end

    get '/requests' do
      erb :requests, locals: { services: @client.services }
    end

    get '/favicon.ico' do
    end

    get '/outages.json' do
      service = @client.service_for_uri_name(name: params[:service])
      if !service
        status 404
        { error: "Service #{params[:service]} not found" }.to_json
      else
        outages = service.outages_in_range(start_time: Time.now - TWO_WEEKS, end_time: Time.now)
        { service: service.uri_name, outages: outages }.to_json
      end
    end

    get '/requests.json' do
      service = @client.service_for_uri_name(name: params[:service])
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

#     helpers do
#       include Rack::Utils
#
#       def url_path(*path_parts)
#         [path_prefix, path_parts].join('/').squeeze('/')
#       end
#       alias_method :u, :url_path
#
#       def path_prefix
#         request.env['SCRIPT_NAME']
#       end
#
#       def url_with_modified_query
#         url = URI(request.url)
#         existing_query = Rack::Utils.parse_query(url.query)
#         url.query = Rack::Utils.build_query(yield existing_query)
#         url.to_s
#       end
#
#       def application_name
#         client.config['application']
#       end
#
#       def queues
#         client.queues.counts
#       end
#
#       def tracked
#         client.jobs.tracked
#       end
#
#       def workers
#         client.workers.counts
#       end
#
#       def failed
#         client.jobs.failed
#       end
#
#       # Return the supplied object back as JSON
#       def json(obj)
#         content_type :json
#         obj.to_json
#       end
#
#       # Make the id acceptable as an id / att in HTML
#       def sanitize_attr(attr)
#         attr.gsub(/[^a-zA-Z\:\_]/, '-')
#       end
#
#     get '/?' do
#       erb :overview, layout: true, locals: { title: 'Overview' }
#     end
#
#     # Returns a JSON blob with the job counts for various queues
#     get '/queues.json' do
#       json(client.queues.counts)
#     end
#
#     get '/queues/?' do
#       erb :queues, layout: true, locals: {
#         title: 'Queues'
#       }
#     end
#
#     # Return the job counts for a specific queue
#     get '/queues/:name.json' do
#       json(client.queues[params[:name]].counts)
#     end
#
#     # start the server if ruby file executed directly
#     run! if app_file == $PROGRAM_NAME
#   end
# end
