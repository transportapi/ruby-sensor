# (c) Copyright IBM Corp. 2021
# (c) Copyright Instana Inc. 2024

# Instana::Rack must always detach the attached OpenTelemetry
# context token, even on a dropped trace where current_span has collapsed to nil
# and finalize_trace's span work is skipped. Otherwise the token leaks into the
# next request on a reused thread.
class RackContextLeakTest < Minitest::Test
  def setup
    @middleware = Instana::Rack.new(->(_env) { [200, {}, ['ok']] })
  end

  def test_finalize_trace_detaches_token_when_not_tracing
    detached = []
    token = OpenTelemetry::Context.attach(OpenTelemetry::Context.current)
    @middleware.instance_variable_set(:@trace_token, token)

    OpenTelemetry::Context.stub(:detach, ->(t) { detached << t }) do
      # current_span nil -> not tracing; span work skipped, but detach must run.
      @middleware.send(:finalize_trace, nil, {}, {}, nil)
    end

    assert_includes detached, token
    assert_nil @middleware.instance_variable_get(:@trace_token)
  end

  def test_finalize_trace_finishes_span_and_detaches_when_tracing
    detached = []
    ctx = Instana::SpanContext.new(trace_id: 'abc123', span_id: 'def456', level: 1)
    span = Instana::Span.new(:rack, ctx)
    token = OpenTelemetry::Context.attach(OpenTelemetry::Context.current)
    @middleware.instance_variable_set(:@trace_token, token)
    ::Instana.tracer.current_span = span

    OpenTelemetry::Context.stub(:detach, ->(t) { detached << t }) do
      ::Instana.processor.stub(:on_finish, ->(_) {}) do
        # headers: nil makes finalize_trace skip set_response_headers (guarded by `if
        # headers`), which would otherwise call active? on the nil trace_context. This
        # test only exercises the span-finish + detach path, not response headers.
        @middleware.send(:finalize_trace, span, {}, nil, nil)
      end
    end

    assert_includes detached, token
    assert_nil @middleware.instance_variable_get(:@trace_token)
  ensure
    ::Instana.tracer.current_span = nil
  end

  def test_finalize_trace_without_token_is_noop_on_detach
    detached = []
    @middleware.instance_variable_set(:@trace_token, nil)

    OpenTelemetry::Context.stub(:detach, ->(t) { detached << t }) do
      @middleware.send(:finalize_trace, nil, {}, {}, nil)
    end

    assert_empty detached
  end
end
