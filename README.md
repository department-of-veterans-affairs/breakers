# Breakers

Breakers is a Ruby gem that implements the circuit breaker pattern for Ruby using a Faraday middleware. It is designed to handle the case
where your app communicates with one or more backend services over HTTP and those services could possibly go down. Data about the success
and failure of requests is recorded in Redis, and the gem uses this to determine when an outage occurs. While a service is marked as down,
requests will continue to flow through occasionally to check if it has returned to being alive.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'breakers'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install breakers

## Quick Start

```ruby
service = Breakers::Service.new(
  name: 'messaging',
  request_matcher: proc { |request_env| request_env.url.host =~ /.*messaging\.va\.gov/ }
)

client = Breakers::Client.new(redis_connection: redis, services: [service])

Breakers.client = client

connection = Faraday.new do |conn|
  conn.use :breakers
  conn.adapter Faraday.default_adapter
end

response = connection.get 'http://messaging.va.gov/query'
```

This will track all requests to messaging.va.gov and will stop sending requests to it for one minute when the error rate reaches 50% over a
two minute period.

## Usage

For more advanced usage and an explanation of the code above, keep reading.

### Services

In an application where you rely on a number of backend services with different endpoints, outage characteristics, and levels of reliability,
breakers lets you configure each of those services globally and then apply a Faraday middleware that uses them to track changes. Services
are defined like this:

```ruby
service = Breakers::Service.new(
  name: 'messaging',
  request_matcher: proc { |request_env| request_env.url.host =~ /.*messaging\.va\.gov/ },
  seconds_before_retry: 60,
  error_threshold: 50
)
```

The name parameter is used for logging and reporting only. On each request, the block will be called with the request's environment, and
the block should return true if the service applies to it.

Each service can be further configured with the following:

* `seconds_before_retry` - The number of seconds to wait before sending a new request when an outage is reported. Every N seconds, a new request will be sent, and if it succeeds the outage will be ended. Defaults to 60.
* `error_threshold` - The percentage of errors over which an outage will be reported. Defaults to 50.
* `data_retention_seconds` - The number of seconds for which data will be stored in Redis for successful and unsuccessful request counts. See below for information on the structure of data within Redis. Defaults to 30 days.

### Client

A Breakers::Client is the data structure that contains all of the information needed to operate the system, and it provides a query API for
accessing the current state. It is initialized with a redis connection and one or more services, with options for a set of plugins and a logger:

```ruby
client = Breakers::Client.new(
  redis_connection: redis,
  services: [service],
  logger: logger,
  plugins: [plugin]
)
```

The logger should conform to Ruby's Logger API. See more information on plugins below.

### Global Configuration

The client can be configured globally with:

```ruby
Breakers.client = client
```

In a Rails app, it makes sense to create the services and client in an initializer and then apply them with this call. If you would like to
namespace the data in Redis with a prefix, you can make that happen with:

```ruby
Breakers.redis_prefix = 'custom-'
```

The default prefix is an empty string.

### Using the Middleware

Once the global configuration is in place, use the middleware as you would normally in Faraday:

```ruby
Faraday.new('http://va.gov') do |conn|
  conn.use :breakers
  conn.adapter Faraday.default_adapter
end
```

### Logging

The client takes an optional `logger:` argument that can accept an object that conforms to Ruby's Logger interface. If provided, it will
log on request errors and outage beginnings and endings.

### Plugins

If you would like to track events in another way, you can also pass plugins to the client with the `plugins:` argument. Plugins should
be instances that implement the following interface:

```ruby
class ExamplePlugin
  def on_outage_begin(outage); end

  def on_outage_end(outage); end

  def on_error(service, request_env, response_env); end

  def on_success(service, request_env, response_env); end
end
```

It's ok for your plugin to implement only part of this interface.

### Forcing an Outage

Some services will have status endpoints that you can use to check their availability, and you may want to create an outage based on that.
Because this is a middleware, it doesn't have the ability to periodically check these endpoints, but you can add that type of check to your
application and then force an outage in breakers:

```ruby
service.begin_forced_outage!
service.end_forced_outage!
```

Unlike with outages detected by the middleware, forced outages are not periodically tested to see if they have completed and must be
manually ended with a call to `end_forced_outage!`.

### Changing the Outage Response

By default, if you make a request against a service that is experiencing an outage a Breakers::OutageException will be raised. If you would
prefer to receive a response with a certain status code instead, you can change that with:

```ruby
Breakers.outage_response = { type: :status_code, status_code: 503 }
```

### Redis Data Structure

Data is stored in Redis with the following structure:

* {prefix}-{service_name}-errors-{unix_timestamp} - A set of keys that store the number of errors by service for each minute. By default these are kept for one month, but you can customize that timestamp with the `data_retention_seconds` argument when creating a service.
* {prefix}-{service_name}-successes-{unix_timestamp} - Same as above but counts for successful requests.
* {prefix}-{service_name}-outages - A sorted set that stores the actual outages. The sort value is the unix timestamp at which the outage occurred, and each entry stores a JSON document containing the start and end times for the outage.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/department-of-veterans-affairs/breakers.

## License

The gem is available as open source under the terms of the Creative Commons Zero 1.0 Universal License.
