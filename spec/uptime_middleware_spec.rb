require 'spec_helper'

describe CircuitBreaker::UptimeMiddleware do
  let(:redis) { Redis.new }
  let(:connection) do
    services = CircuitBreaker::Services.new
    services.add_service(
      name: 'facebook',
      host: /.*facebook.com/,
      path: /.*/
    )
    Faraday.new(url: 'http://www.facebook.com') do |conn|
      conn.use :circuit_breaker, redis, services
      conn.adapter Faraday.default_adapter
    end
  end

  context 'with a 500' do
    before do
      stub_request(:get, 'www.facebook.com').to_return(status: 500)
    end

    it 'adds a failure to redis' do
      connection.get '/'
      expect(redis.zcount('cb-facebook-errors', 0, Time.now.to_i)).to eq(1)
      items = redis.zrange('cb-facebook-errors', 0, Time.now.to_i)
      expect(MultiJson.load(items[0])).to eq('issue' => 'status', 'status' => 500)
    end
  end

  context 'with a timeout' do
    before do
      stub_request(:get, 'www.facebook.com').to_timeout
    end

    it 'adds a failure to redis' do
      connection.get '/'
      expect(redis.zcount('cb-facebook-errors', 0, Time.now.to_i)).to eq(1)
      items = redis.zrange('cb-facebook-errors', 0, Time.now.to_i)
      expect(MultiJson.load(items[0])).to eq('issue' => 'timeout')
    end
  end

  context 'there is an outage' do
    let(:start_time) { Time.now - 1.hour }
    before do
      Timecop.freeze(start_time)
      redis.zadd('cb-facebook-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i))
    end

    it 'should return a 503' do
      response = connection.get '/'
      expect(response.status).to eq(503)
    end
  end
end
