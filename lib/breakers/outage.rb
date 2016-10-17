require 'multi_json'

module Breakers
  class Outage
    attr_reader :service
    attr_reader :body

    def self.find_last(service:)
      data = Breakers.client.redis_connection.zrange(outages_key(service: service), -1, -1)[0]
      data && new(service: service, data: data)
    end

    def self.in_range(service:, start_time:, end_time:)
      data = Breakers.client.redis_connection.zrangebyscore(
        outages_key(service: service),
        start_time.to_i,
        end_time.to_i
      )
      data.map { |item| new(service: service, data: item) }
    end

    def self.create(service:)
      data = MultiJson.dump(start_time: Time.now.utc.to_i)
      Breakers.client.redis_connection.zadd(outages_key(service: service), Time.now.utc.to_i, data)

      Breakers.client.logger&.error(msg: 'Breakers outage beginning', service: service.name)

      Breakers.client.plugins.each do |plugin|
        plugin.on_outage_begin(Outage.new(service: service, data: data)) if plugin.respond_to?(:on_outage_begin)
      end
    end

    def self.outages_key(service:)
      "#{Breakers.redis_prefix}#{service.name}-outages"
    end

    def initialize(service:, data:)
      @body = MultiJson.load(data)
      @service = service
    end

    def ended?
      @body.key?('end_time')
    end

    def end!
      new_body = @body.dup
      new_body['end_time'] = Time.now.utc.to_i
      replace_body(body: new_body)

      Breakers.client.logger&.info(msg: 'Breakers outage ending', service: @service.name)
      Breakers.client.plugins.each do |plugin|
        plugin.on_outage_end(self) if plugin.respond_to?(:on_outage_begin)
      end
    end

    def start_time
      @body['start_time'] && Time.at(@body['start_time']).utc
    end

    def end_time
      @body['end_time'] && Time.at(@body['end_time']).utc
    end

    def last_test_time
      (@body['last_test_time'] && Time.at(@body['last_test_time']).utc) || start_time
    end

    def update_last_test_time!
      new_body = @body.dup
      new_body['last_test_time'] = Time.now.utc.to_i
      replace_body(body: new_body)
    end

    def ready_for_retest?(wait_seconds:)
      (Time.now.utc - last_test_time) > wait_seconds
    end

    protected

    def key
      "#{Breakers.redis_prefix}#{@service.name}-outages"
    end

    def replace_body(body:)
      Breakers.client.redis_connection.multi do
        Breakers.client.redis_connection.zrem(key, MultiJson.dump(@body))
        Breakers.client.redis_connection.zadd(key, start_time.to_i, MultiJson.dump(body))
      end
      @body = body
    end
  end
end
