require 'logger'
require 'spec_helper'

describe 'integration suite' do
  let(:redis) { Redis.new }
  let(:service) do
    Breakers::Service.new(
      name: 'VA',
      request_matcher: proc { |request_env| request_env.url.host =~ /.*va.gov/ },
      seconds_before_retry: 60,
      error_threshold: 50
    )
  end
  let(:logger) { Logger.new(nil) }
  let(:plugin) { ExamplePlugin.new }
  let(:client) do
    Breakers::Client.new(
      redis_connection: redis,
      services: [service],
      logger: logger,
      plugins: [plugin]
    )
  end
  let(:connection) do
    Faraday.new('http://va.gov') do |conn|
      conn.use :breakers
      conn.adapter Faraday.default_adapter
    end
  end

  before do
    Breakers.outage_response = { type: :status_code, status_code: 503 }
    Breakers.client = client
  end

  context 'with a 500' do
    let(:now) { Time.now.utc }

    before do
      Timecop.freeze(now)
      stub_request(:get, 'va.gov').to_return(status: 500)
    end

    it 'adds a failure to redis' do
      connection.get '/'
      rounded_time = now.to_i - (now.to_i % 60)
      expect(redis.get("VA-errors-#{rounded_time.to_i}").to_i).to eq(1)
    end

    it 'creates an outage' do
      connection.get '/'
      expect(service.latest_outage).to be
    end

    context 'with min_errors' do
      let(:service) do
        Breakers::Service.new(
          name: 'VA',
          request_matcher: proc { |request_env| request_env.url.host =~ /.*va.gov/ },
          seconds_before_retry: 60,
          error_threshold: 50,
          min_errors: 3
        )
      end

      it 'does not create an outage with a single error' do
        connection.get '/'
        expect(service.latest_outage).to be_nil
      end

      it 'creates an outage after many errors' do
        3.times { connection.get '/' }
        expect(service.latest_outage).to be_truthy
      end
    end

    it 'logs the error' do
      expect(logger).to receive(:warn).with(
        msg: 'Breakers failed request', service: 'VA', url: 'http://va.gov/', error: 500
      )
      connection.get '/'
    end

    it 'tells plugins about the error' do
      expect(plugin).to receive(:on_error).with(service, instance_of(Faraday::Env), instance_of(Faraday::Env))
      connection.get '/'
    end

    it 'logs the outage' do
      expect(logger).to receive(:error).with(msg: 'Breakers outage beginning', service: 'VA', forced: false)
      connection.get '/'
    end

    it 'tells plugins about the outage' do
      expect(plugin).to receive(:on_outage_begin).with(instance_of(Breakers::Outage))
      connection.get '/'
    end

    it 'lets me query for errors in a time range' do
      connection.get '/'
      counts = service.errors_in_range(start_time: now - 120, end_time: now, sample_minutes: 1)
      count = counts.map { |c| c[:count] }.inject(0) { |a, b| a + b }
      expect(count).to eq(1)
    end

    context 'with breakers disabled' do
      before do
        Breakers.disabled = true
      end

      after do
        Breakers.disabled = false
      end

      it 'does not add a failure to redis' do
        connection.get '/'
        rounded_time = now.to_i - (now.to_i % 60)
        expect(redis.get("VA-errors-#{rounded_time.to_i}").to_i).to eq(0)
      end

      it 'does not create an outage' do
        connection.get '/'
        expect(service.latest_outage).not_to be
      end

      it 'does not log the error' do
        expect(logger).not_to receive(:warn)
        connection.get '/'
      end

      it 'does not tell plugins about the error' do
        expect(plugin).not_to receive(:on_error)
        connection.get '/'
      end

      it 'does not log the outage' do
        expect(logger).not_to receive(:error)
        connection.get '/'
      end

      it 'does not tell plugins about the outage' do
        expect(plugin).not_to receive(:on_outage_begin)
        connection.get '/'
      end

      it 'stores no errors in the time range' do
        connection.get '/'
        counts = service.errors_in_range(start_time: now - 120, end_time: now, sample_minutes: 1)
        count = counts.map { |c| c[:count] }.inject(0) { |a, b| a + b }
        expect(count).to eq(0)
      end
    end
  end

  context 'with a timeout' do
    let(:now) { Time.now.utc }

    before do
      Timecop.freeze(now)
      stub_request(:get, 'va.gov').to_timeout
    end

    it 'adds a failure to redis' do
      begin
        connection.get '/'
      rescue Faraday::ConnectionFailed
      end
      rounded_time = now.to_i - (now.to_i % 60)
      expect(redis.get("VA-errors-#{rounded_time.to_i}").to_i).to eq(1)
    end

    it 'raises the exception' do
      expect { connection.get '/' }.to raise_error(Faraday::ConnectionFailed)
    end

    it 'logs the error' do
      expect(logger).to receive(:warn).with(
        msg: 'Breakers failed request', service: 'VA', url: 'http://va.gov/', error: 'Faraday::ConnectionFailed - execution expired'
      )

      begin
        connection.get '/'
      rescue Faraday::ConnectionFailed
      end
    end

    it 'tells plugins about the timeout' do
      expect(plugin).to receive(:on_error).with(service, instance_of(Faraday::Env), nil)
      begin
        connection.get '/'
      rescue Faraday::ConnectionFailed
      end
    end
  end

  context 'with some other error' do
    let(:now) { Time.now.utc }

    context 'without an error handler' do
      before do
        Timecop.freeze(now)
        stub_request(:get, 'va.gov').to_raise('bogus error')
      end

      it 'does not add a failure to redis' do
        begin
          connection.get '/'
        rescue
        end
        rounded_time = now.to_i - (now.to_i % 60)
        expect(redis.get("VA-errors-#{rounded_time.to_i}").to_i).to eq(0)
      end

      it 'raises the exception' do
        expect { connection.get '/' }.to raise_error(StandardError)
      end

      it 'does not log the error' do
        expect(logger).not_to receive(:warn).with(
          msg: 'Breakers failed request', service: 'VA', url: 'http://va.gov/', error: 'StandardError - bogus error'
        )

        begin
          connection.get '/'
        rescue
        end
      end

      it 'does not tell plugins about the timeout' do
        expect(plugin).not_to receive(:on_error).with(service, instance_of(Faraday::Env), nil)
        begin
          connection.get '/'
        rescue
        end
      end
    end

    context 'with an error handler' do
      let(:service) do
        Breakers::Service.new(
          name: 'VA',
          request_matcher: proc { |request_env| request_env.url.host =~ /.*va.gov/ },
          seconds_before_retry: 60,
          error_threshold: 50,
          exception_handler: proc { |e| true }
        )
      end

      before do
        Timecop.freeze(now)
        stub_request(:get, 'va.gov').to_raise('bogus error')
      end

      it 'adds a failure to redis' do
        begin
          connection.get '/'
        rescue
        end
        rounded_time = now.to_i - (now.to_i % 60)
        expect(redis.get("VA-errors-#{rounded_time.to_i}").to_i).to eq(1)
      end

      it 'raises the exception' do
        expect { connection.get '/' }.to raise_error(StandardError)
      end

      it 'logs the error' do
        expect(logger).to receive(:warn).with(
          msg: 'Breakers failed request', service: 'VA', url: 'http://va.gov/', error: 'StandardError - bogus error'
        )

        begin
          connection.get '/'
        rescue
        end
      end

      it 'tells plugins about the timeout' do
        expect(plugin).to receive(:on_error).with(service, instance_of(Faraday::Env), nil)
        begin
          connection.get '/'
        rescue
        end
      end
    end
  end

  context 'there is an outage that started less than a minute ago' do
    let(:start_time) { Time.now.utc - 30 }
    let(:now) { Time.now.utc }
    before do
      Timecop.freeze(now)
      redis.zadd('VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i))
    end

    it 'should return a 503' do
      response = connection.get '/'
      expect(response.status).to eq(503)
    end

    it 'should tell the plugin about the skipped request during outage' do
      expect(plugin).to receive(:on_skipped_request).with(service)
      begin
        connection.get '/'
      rescue
      end
    end

    it 'should include information about the outage in the body' do
      response = connection.get '/'
      expect(response.body).to eq("Outage detected on VA beginning at #{start_time.to_i}")
    end
  end

  context 'there is a completed outage with guaranteed success INCRs' do
    let(:start_time) { Time.now.utc - (60 * 60) }
    let(:end_time) { Time.now.utc - 60 }
    let(:now_time) { Time.now.utc }
    before do
      service.instance_variable_get(:@configuration)[:success_sample_per] = 1
      Timecop.freeze(now_time)
      redis.zadd('VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i, end_time: end_time))
      stub_request(:get, 'va.gov').to_return(status: 200)
    end

    it 'makes the request' do
      response = connection.get '/'
      expect(response.status).to eq(200)
    end

    it 'adds a success to redis' do
      connection.get '/'
      rounded_time = now_time.to_i - (now_time.to_i % 60)
      count = redis.get("VA-successes-#{rounded_time}")
      expect(count).to eq('1')
    end

    it 'adds two successes to redis' do
      response = connection.get '/'
      response = connection.get '/'
      rounded_time = now_time.to_i - (now_time.to_i % 60)
      count = redis.get("VA-successes-#{rounded_time}")
      expect(count).to eq('2')
    end

    it 'informs the plugin about a success' do
      expect(plugin).to receive(:on_success).with(service, instance_of(Faraday::Env), instance_of(Faraday::Env))
      connection.get '/'
    end

    it 'should not tell the plugin about a skipped request' do
      expect(plugin).not_to receive(:on_skipped_request)
      connection.get '/'
    end
  end

  context 'there is a completed outage with pseudo-random success INCRs' do
    let(:start_time) { Time.now.utc - (60 * 60) }
    let(:end_time) { Time.now.utc - 60 }
    let(:now_time) { Time.now.utc }
    before do
      service.instance_variable_get(:@configuration)[:success_sample_per] = 2
      Timecop.freeze(now_time)
      redis.zadd('VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i, end_time: end_time))
      stub_request(:get, 'va.gov').to_return(status: 200)
    end

    # Wrap the examples to ensure exactly half of status messages get written
    # to (our mocked in-memory) redis, alternating, starting with false.
    def silence_warnings
      original_verbosity = $VERBOSE
      $VERBOSE = nil
      result = yield
      $VERBOSE = original_verbosity
      result
    end
    around(:example) do |example|
      silence_warnings do
        class Breakers::Service
          @@_fake_rand = [0.75, 0.25]
          def rand
            @@_fake_rand.push(@@_fake_rand.shift)
            @@_fake_rand[-1]
          end
        end
      end
      result = example.run
      silence_warnings do
        class Breakers::Service
          remove_method :rand
        end
      end
      result
    end

    it 'makes the request' do
      response = connection.get '/'
      expect(response.status).to eq(200)
    end

    it 'adds success to redis after every other request' do
      rounded_time = now_time.to_i - (now_time.to_i % 60)
      response = connection.get '/'
      count = redis.get("VA-successes-#{rounded_time}")
      expect(count).to eq(nil)
      response = connection.get '/'
      count = redis.get("VA-successes-#{rounded_time}")
      expect(count).to eq('2')
      response = connection.get '/'
      count = redis.get("VA-successes-#{rounded_time}")
      expect(count).to eq('2')
      response = connection.get '/'
      count = redis.get("VA-successes-#{rounded_time}")
      expect(count).to eq('4')
    end

    it 'informs the plugin about a success regardless of sample_per' do
      expect(plugin).to receive(:on_success).with(service, instance_of(Faraday::Env), instance_of(Faraday::Env))
      connection.get '/'
    end

    it 'should not tell the plugin about a skipped request' do
      expect(plugin).not_to receive(:on_skipped_request)
      connection.get '/'
    end
  end

  context 'there is an outage that started over a minute ago' do
    let(:start_time) { Time.now.utc - 120 }
    let(:now) { Time.now.utc }
    before do
      Timecop.freeze(now)
      redis.zadd('VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i, forced: false))
    end

    it 'lets me query for the outage by time range' do
      outages = service.outages_in_range(start_time: start_time, end_time: now)
      expect(outages.count).to eq(1)
      expect(outages.first.start_time.to_i).to eq(start_time.to_i)
      expect(outages.first.end_time).to be_nil
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
        expect(service.latest_outage).to be_ended
      end

      it 'logs the end of the outage' do
        expect(logger).to receive(:info).with(msg: 'Breakers outage ending', service: 'VA', forced: false)
        connection.get '/'
      end

      it 'tells the plugin about the end of the outage' do
        expect(plugin).to receive(:on_outage_end).with(instance_of(Breakers::Outage))
        connection.get '/'
      end

      it 'records the end time in the outage' do
        connection.get '/'
        expect(service.latest_outage.end_time.to_i).to eq(now.to_i)
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
        expect(service.latest_outage.last_test_time.to_i).to eq(now.to_i)
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
    let(:now) { Time.now.utc }
    before do
      service.instance_variable_get(:@configuration)[:success_sample_per] = 2
    end

    # Wrap the examples to ensure exactly half of status messages get written
    # to (our mocked in-memory) redis, alternating, starting with false.
    def silence_warnings
      original_verbosity = $VERBOSE
      $VERBOSE = nil
      result = yield
      $VERBOSE = original_verbosity
      result
    end
    around(:example) do |example|
      silence_warnings do
        class Breakers::Service
          @@_fake_rand = [0.75, 0.25]
          def rand
            @@_fake_rand.push(@@_fake_rand.shift)
            @@_fake_rand[-1]
          end
        end
      end
      result = example.run
      silence_warnings do
        class Breakers::Service
          remove_method :rand
        end
      end
      result
    end

    before do
      Timecop.freeze(now - 90)
      stub_request(:get, 'va.gov').to_return(status: 200, body: 'abcdef')
      60.times { connection.get '/' }

      Timecop.freeze(now - 30)
      stub_request(:get, 'va.gov').to_return(status: 200, body: 'abcdef')
      40.times { connection.get '/' }
    end

    it 'does not record an outage on a single failure' do
      stub_request(:get, 'va.gov').to_return(status: 500)
      connection.get '/'
      expect(service.latest_outage).not_to be
    end

    it 'does not record an outage after 99 errors' do
      stub_request(:get, 'va.gov').to_return(status: 500)
      99.times { connection.get '/' }
      expect(service.latest_outage).not_to be
    end

    it 'records an outage after 100 errors' do
      stub_request(:get, 'va.gov').to_return(status: 500)
      100.times { connection.get '/' }
      expect(service.latest_outage).to be
    end

    it 'lets me query for successes in a time range' do
      counts = service.successes_in_range(start_time: now - 120, end_time: now, sample_minutes: 1)
      count = counts.map { |c| c[:count] }.inject(0) { |a, b| a + b }
      expect(count).to eq(100)
    end
  end

  context 'starting a forced outage' do
    it 'logs the beginning of the outage' do
      expect(logger).to receive(:error).with(msg: 'Breakers outage beginning', service: 'VA', forced: true)
      service.begin_forced_outage!
    end

    it 'logs the end of the outage' do
      expect(logger).to receive(:info).with(msg: 'Breakers outage ending', service: 'VA', forced: true)
      service.begin_forced_outage!
      service.end_forced_outage!
    end
  end

  context 'there is a forced outage' do
    let(:start_time) { Time.now.utc - 120 }
    let(:now) { Time.now.utc }
    before do
      Timecop.freeze(start_time)
      service.begin_forced_outage!
      Timecop.freeze(now)
    end

    it 'lets me end the outage' do
      expect(service.latest_outage).to be_forced
      expect(service.latest_outage).not_to be_ended
      service.end_forced_outage!
      expect(service.latest_outage).to be_forced
      expect(service.latest_outage).to be_ended
    end

    it 'lets me query for the outage by time range' do
      outages = service.outages_in_range(start_time: start_time, end_time: now)
      expect(outages.count).to eq(1)
      expect(outages.first.start_time.to_i).to eq(start_time.to_i)
      expect(outages.first.end_time).to be_nil
      expect(outages.first).to be_forced
    end

    context 'and the new request is successful' do
      before do
        stub_request(:get, 'va.gov').to_return(status: 200, body: 'abcdef')
      end

      it 'should not make the request' do
        connection.get '/'
        expect(WebMock).not_to have_requested(:get, 'va.gov')
      end

      it 'returns a 503' do
        response = connection.get '/'
        expect(response.status).to eq(503)
      end

      it 'does not call off the outage' do
        connection.get '/'
        expect(service.latest_outage).not_to be_ended
      end
    end
  end

  context 'configured to raise exceptions' do
    let(:start_time) { Time.now.utc - 30 }
    let(:now) { Time.now.utc }
    before do
      Timecop.freeze(now)
      redis.zadd('VA-outages', start_time.to_i, MultiJson.dump(start_time: start_time.to_i))
    end

    before do
      Breakers.outage_response = { type: :exception }
    end

    it 'raises the exception' do
      expect { connection.get '/' }.to raise_error(Breakers::OutageException)
    end
  end

  context 'with a 200' do
    let(:now) { Time.now.utc }

    before do
      Timecop.freeze(now)
      stub_request(:get, 'va.gov').to_return(status: 200)
    end

    it 'gives me the request duration' do
      response = connection.get '/'
      expect(response.env[:duration]).to be
    end
  end

  context 'with throttling of outage checks' do
    let(:now) { Time.now.utc }
    let(:service) do
      Breakers::Service.new(
        name: 'VA',
        request_matcher: proc { |request_env| request_env.url.host =~ /.*va.gov/ },
        seconds_before_retry: 60,
        error_threshold: 50,
        seconds_between_outage_checks: 10
      )
    end

    it 'only checks for outages once every 10 seconds' do
      expect(redis).to receive(:zrange).twice.and_return([])
      2.times { service.latest_outage }
      Timecop.freeze(now + 10)
      2.times { service.latest_outage }
      Timecop.return
    end
  end
end
