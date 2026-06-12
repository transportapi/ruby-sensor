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
    token = :fake_token

    OpenTelemetry::Context.stub(:detach, ->(t) { detached << t }) do
      @middleware.send(:finalize_trace, nil, {}, {}, nil, token)
    end

    assert_includes detached, token
  end

  def test_finalize_trace_finishes_span_and_detaches_when_tracing
    detached = []
    ctx = Instana::SpanContext.new(trace_id: 'abc123', span_id: 'def456', level: 1)
    span = Instana::Span.new(:rack, ctx)
    token = :fake_token
    ::Instana.tracer.current_span = span

    OpenTelemetry::Context.stub(:detach, ->(t) { detached << t }) do
      ::Instana.processor.stub(:on_finish, ->(_) {}) do
        @middleware.send(:finalize_trace, span, {}, nil, nil, token)
      end
    end

    assert_includes detached, token
  ensure
    ::Instana.tracer.current_span = nil
  end

  def test_concurrent_calls_do_not_share_token
    attached = Queue.new
    detached = Queue.new
    call_count = 0

    app = lambda { |_env|
      call_count += 1
      sleep 0.05 # widen the race window
      [200, {}, ['ok']]
    }
    middleware = Instana::Rack.new(app)

    OpenTelemetry::Context.stub(:attach, lambda { |_|
      token = Object.new
      attached << token
      token
    }) do
      OpenTelemetry::Context.stub(:detach, ->(t) { detached << t }) do
        threads = 5.times.map { Thread.new { middleware.call({}) } }
        threads.each(&:join)
      end
    end

    # Every attached token must have a matching detach — no token lost or doubled.
    attached_set = []
    detached_set = []
    attached_set << attached.pop until attached.empty?
    detached_set << detached.pop until detached.empty?
    assert_equal attached_set.sort_by(&:object_id), detached_set.sort_by(&:object_id)
  end
end
