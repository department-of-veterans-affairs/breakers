# Breakers

Breakers is a Ruby gem that implements the circuit breaker pattern for Ruby using a Faraday middleware. It is designed to handle the case
where your app communicates with one or more backend services over HTTP and those services could possibly go down. Data about the success
and failure of requests is recorded in Redis, and the gem uses this to determine when an outage occurs. While a service is marked as down,
requests will continue to flow through every minute to check if it has returned to being alive.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'breakers'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install breakers

## Usage

### Getting Connected

The gem allows you to define your services like this:

```ruby
service = Breakers::Service.new(name: 'messaging', host: /.*messaging\.va\.gov/, path: /.*/)
```

The name parameter is used for logging and reporting only. On each request, the host and path will be compared against the requested values
to see if this service applies.

A Breakers::Client is the basic data structure for accessing the state and creating connections. It requires a redis connection and one or
more services:

```ruby
client = Breakers::Client.new(redis_connection: redis, services: [service])
Breakers.set_client(client)
```

Now, you can create a new Faraday connection in your code with:

```ruby
Breakers.new_connection
```

This method takes optional `url:` and `adapter:` arguments to allow you to customize those values in the connection.

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/department-of-veterans-affairs/breakers.

## License

The gem is available as open source under the terms of the Creative Commons Zero 1.0 Universal License.
