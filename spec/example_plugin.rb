class ExamplePlugin
  def on_outage_begin(outage); end

  def on_outage_end(outage); end

  def on_skipped_request(service); end

  def on_error(service, request_env, response_env); end

  def on_success(service, request_env, response_env); end
end
