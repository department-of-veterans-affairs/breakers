require 'spec_helper'

describe CircuitBreaker::UptimeMiddleware do
  let(:redis) { Redis.new }
  let(:service) do
    CircuitBreaker::Service.new(
      name: 'VA',
      host: /.*va.gov/,
      path: /.*/
    )
  end
  let(:logger) { Logger.new(nil) }
  let(:plugin) { ExamplePlugin.new }
  let(:client) do
    CircuitBreaker::Client.new(
      redis_connection: redis,
      services: [service],
      logger: logger,
      plugins: [plugin]
    )
  end
  let(:connection) do
    Faraday.new(url: 'http://va.gov') do |conn|
      conn.use :circuit_breaker, client
      conn.adapter Faraday.default_adapter
    end
  end

  context 'with a 500' do
    let(:now) { Time.now }

    before do
      Timecop.freeze(now)
      stub_request(:get, 'va.gov').to_return(status: 500)
    end

    it 'adds a failure to redis' do
      connection.get '/'
      rounded_time = now.to_i - (now.to_i % 60)
      expect(redis.get("cb-VA-errors-#{rounded_time.to_i}").to_i).to eq(1)
    end

    it 'creates an outage' do
      connection.get '/'
      expect(service.last_outage).to be
    end

    it 'logs the error' do
      expect(logger).to receive(:warn).with(
        msg: 'CircuitBreaker failed request', service: 'VA', url: 'http://va.gov/', error: 500
      )
      connection.get '/'
    end

    it 'tells plugins about the error' do
      expect(plugin).to receive(:on_error).with(service, instance_of(Faraday::Env), instance_of(Faraday::Env))
      connection.get '/'
    end

    it 'logs the outage' do
      expect(logger).to receive(:error).with(msg: 'CircuitBreaker outage beginning', service: 'VA')
      connection.get '/'
    end

    it 'tells plugins about the outage' do
      expect(plugin).to receive(:on_outage_begin).with(instance_of(CircuitBreaker::Outage))
      connection.get '/'
    end
  end

  context 'with a timeout' do
    let(:now) { Time.now }

    before do
      Timecop.freeze(now)
      stub_request(:get, 'va.gov').to_timeout
    end

    it 'adds a failure to redis' do
      connection.get '/'
      rounded_time = now.to_i - (now.to_i % 60)
      expect(redis.get("cb-VA-errors-#{rounded_time.to_i}").to_i).to eq(1)
    end

    it 'logs the error' do
      expect(logger).to receive(:warn).with(
        msg: 'CircuitBreaker failed request', service: 'VA', url: 'http://va.gov/', error: 'timeout'
      )
      connection.get '/'
    end

    it 'tells plugins about the timeout' do
      expect(plugin).to receive(:on_error).with(service, instance_of(Faraday::Env), nil)
      connection.get '/'
    end
  end

  context 'there is an outage that started less than a minute ago' do
    let(:start_time) { Time.now - 30.seconds }
    let(:now) { Time.now }
    before do
      Timecop.freeze(now)
      redis.zadd('cb-VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i))
    end

    it 'should return a 503' do
      response = connection.get '/'
      expect(response.status).to eq(503)
    end

    it 'should include information about the outage in the body' do
      response = connection.get '/'
      expect(response.body).to eq("Outage detected on VA beginning at #{start_time.to_i}")
    end
  end

  context 'there is a completed outage' do
    let(:start_time) { Time.now - 1.hour }
    let(:end_time) { Time.now - 1.minute }
    let(:now_time) { Time.now }
    before do
      Timecop.freeze(now_time)
      redis.zadd('cb-VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i, end_time: end_time))
      stub_request(:get, 'va.gov').to_return(status: 200)
    end

    it 'makes the request' do
      response = connection.get '/'
      expect(response.status).to eq(200)
    end

    it 'adds a success to redis' do
      connection.get '/'
      rounded_time = now_time.to_i - (now_time.to_i % 60)
      count = redis.get("cb-VA-successes-#{rounded_time}")
      expect(count).to eq('1')
    end

    it 'informs the plugin about the success' do
      expect(plugin).to receive(:on_success).with(service, instance_of(Faraday::Env), instance_of(Faraday::Env))
      connection.get '/'
    end
  end

  context 'there is an outage that started over a minute ago' do
    let(:start_time) { Time.now - 2.minutes }
    let(:now) { Time.now }
    before do
      Timecop.freeze(now)
      redis.zadd('cb-VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i))
    end

    context 'and the new request is successful' do
      before do
        stub_request(:get, 'va.gov').to_return(status: 200, body: 'abcdef')
      end

      it 'should make the request' do
        connection.get '/'
        expect(WebMock).to have_requested(:get, 'va.gov')
      end

      it 'returns the data from the response' do
        response = connection.get '/'
        expect(response.body).to eq('abcdef')
        expect(response.status).to eq(200)
      end

      it 'calls off the outage' do
        connection.get '/'
        expect(service.last_outage).to be_ended
      end

      it 'logs the end of the outage' do
        expect(logger).to receive(:info).with(msg: 'CircuitBreaker outage ending', service: 'VA')
        connection.get '/'
      end

      it 'tells the plugin about the end of the outage' do
        expect(plugin).to receive(:on_outage_end).with(instance_of(CircuitBreaker::Outage))
        connection.get '/'
      end
    end

    context 'and the new request is not successful' do
      before do
        stub_request(:get, 'va.gov').to_return(status: 500, body: 'abcdef')
      end

      it 'should make the request' do
        connection.get '/'
        expect(WebMock).to have_requested(:get, 'va.gov')
      end

      it 'returns a 500' do
        response = connection.get '/'
        expect(response.status).to eq(500)
      end

      it 'updates the last_test_time in the outate' do
        connection.get '/'
        expect(service.last_outage.last_test_time.to_i).to eq(now.to_i)
      end

      it 'gets a 503 when making another request' do
        connection.get '/'
        response = connection.get '/'
        expect(response.status).to eq(503)
      end
    end
  end

  context 'on a request to a non-service' do
    before do
      stub_request(:get, 'http://whitehouse.gov').to_return(status: 200, body: 'POTUS')
    end

    it 'returns the status and body from the response' do
      response = connection.get('http://whitehouse.gov')
      expect(response.status).to eq(200)
      expect(response.body).to eq('POTUS')
    end
  end

  context 'with a bunch of successes over the last few minutes' do
    let(:now) { Time.now }

    before do
      Timecop.freeze(now - 90.seconds)
      stub_request(:get, 'va.gov').to_return(status: 200, body: 'abcdef')
      60.times { connection.get '/' }

      Timecop.freeze(now - 30.seconds)
      stub_request(:get, 'va.gov').to_return(status: 200, body: 'abcdef')
      40.times { connection.get '/' }
    end

    it 'does not record an outage on a single failure' do
      stub_request(:get, 'va.gov').to_return(status: 500)
      connection.get '/'
      expect(service.last_outage).not_to be
    end

    it 'does not record an outage after 99 errors' do
      stub_request(:get, 'va.gov').to_return(status: 500)
      99.times { connection.get '/' }
      expect(service.last_outage).not_to be
    end

    it 'records an outage after 100 errors' do
      stub_request(:get, 'va.gov').to_return(status: 500)
      100.times { connection.get '/' }
      expect(service.last_outage).to be
    end
  end
end
