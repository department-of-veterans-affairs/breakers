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

  context 'there is an outage that started less than a minute ago' do
    let(:start_time) { Time.now - 30.seconds }
    let(:now) { Time.now }
    before do
      Timecop.freeze(now)
      redis.zadd('cb-facebook-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i))
    end

    it 'should return a 503' do
      response = connection.get '/'
      expect(response.status).to eq(503)
    end

    it 'should include information about the outage in the body' do
      response = connection.get '/'
      expect(response.body).to eq("Outage detected on facebook beginning at #{start_time.to_i}")
    end
  end

  context 'there is a completed outage' do
    let(:start_time) { Time.now - 1.hour }
    let(:end_time) { Time.now - 1.minute }
    let(:now_time) { Time.now }
    before do
      Timecop.freeze(now_time)
      redis.zadd('cb-facebook-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i, end_time: end_time))
      stub_request(:get, 'www.facebook.com').to_return(status: 200)
    end

    it 'makes the request' do
      response = connection.get '/'
      expect(response.status).to eq(200)
    end
  end

  context 'there is an outage that started over a minute ago' do
    let(:start_time) { Time.now - 2.minutes }
    let(:now) { Time.now }
    before do
      Timecop.freeze(now)
      redis.zadd('cb-facebook-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i))
    end

    context 'and the new request is successful' do
      before do
        stub_request(:get, 'www.facebook.com').to_return(status: 200)
      end

      it 'should make the request' do
        response = connection.get '/'
        expect(WebMock).to have_requested(:get, 'www.facebook.com')
      end
    end
  end
end
