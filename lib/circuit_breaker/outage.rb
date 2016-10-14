require 'multi_json'

module CircuitBreaker
  class Outage
    attr_reader :service

    def self.find_last(client:, service:)
      data = client.redis_connection.zrange("cb-#{service.name}-outages", -1, -1)[0]
      data && new(client: client, service: service, data: data)
    end

    def self.in_range(client:, service:, start_time:, end_time:)
      data = client.redis_connection.zrangebyscore(
        "cb-#{service.name}-outages",
        start_time.to_i,
        end_time.to_i
      )
      data.map { |item| new(client: client, service: service, data: item) }
    end

    def self.create(client:, service:)
      data = MultiJson.dump(start_time: Time.now.to_i)
      client.redis_connection.zadd("cb-#{service.name}-outages", Time.now.to_i, data)

      client.logger&.error(msg: 'CircuitBreaker outage beginning', service: service.name)

      client.plugins.each do |plugin|
        plugin.on_outage_begin(Outage.new(client: client, service: service, data: data)) if plugin.respond_to?(:on_outage_begin)
      end
    end

    def initialize(client:, service:, data:)
      @body = MultiJson.load(data)
      @service = service
      @client = client
    end

    def to_json(*options)
      @body.to_json(*options)
    end

    def ended?
      @body.key?('end_time')
    end

    def end!
      new_body = @body.dup
      new_body['end_time'] = Time.now.to_i
      replace_body(body: new_body)

      @client.logger&.info(msg: 'CircuitBreaker outage ending', service: @service.name)
      @client.plugins.each do |plugin|
        plugin.on_outage_end(self) if plugin.respond_to?(:on_outage_begin)
      end
    end

    def start_time
      Time.at(@body['start_time'])
    end

    def end_time
      Time.at(@body['end_time'])
    end

    def last_test_time
      (@body['last_test_time'] && Time.at(@body['last_test_time'])) || start_time
    end

    def update_last_test_time!
      new_body = @body.dup
      new_body['last_test_time'] = Time.now.to_i
      replace_body(body: new_body)
    end

    def ready_for_retest?
      (Time.now - last_test_time) > 60
    end

    protected

    def key
      "cb-#{@service.name}-outages"
    end

    def replace_body(body:)
      @client.redis_connection.multi do
        @client.redis_connection.zrem(key, MultiJson.dump(@body))
        @client.redis_connection.zadd(key, start_time.to_i, MultiJson.dump(body))
      end
      @body = body
    end
  end
end
