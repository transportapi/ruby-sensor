# (c) Copyright IBM Corp. 2025
# (c) Copyright Instana Inc. 2025

require 'test_helper'
require 'instana/trace/tracer_provider'
require 'instana/trace/export'

class TracerProviderTest < Minitest::Test
  def setup
    @tracer_provider = Instana.tracer_provider
  end

  def dropping_provider
    ::Instana::Trace::TracerProvider.new(sampler: Instana::TestSupport.dropping_sampler)
  end

  def keeping_provider
    ::Instana::Trace::TracerProvider.new(sampler: Instana::TestSupport.keeping_sampler)
  end

  def start_root(provider, name: :rack)
    provider.internal_start_span(name, :internal, {}, [], Time.now, nil, nil)
  end

  def test_tracer
    # This tests the global tracer is the same as tracer from tracer_provider
    assert_equal Instana.tracer, @tracer_provider.tracer("instana_tracer")
  end

  def test_shutdown_with_timeout
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    timeout = 10
    result = @tracer_provider.shutdown(timeout: timeout)
    assert_equal Instana::Trace::Export::SUCCESS, result
    @span_processors = @tracer_provider.instance_variable_get(:@span_processors)
    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
    assert_equal [Instana::Trace::Export::SUCCESS], @tracer_provider.instance_variable_get(:@span_processors).map(&:shutdown)
    assert @tracer_provider.instance_variable_get(:@stopped)
  end

  def test_shutdown_without_timeout
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    # @tracer = @tracer_provider.tracer('test_shutdown_without_timeout')
    result = @tracer_provider.shutdown
    assert_equal Instana::Trace::Export::SUCCESS, result

    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
    assert_equal [Instana::Trace::Export::SUCCESS], @tracer_provider.instance_variable_get(:@span_processors).map(&:shutdown)
    assert @tracer_provider.instance_variable_get(:@stopped)
  end

  def test_shutdown_called_multiple_times
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    # @tracer = @tracer_provider.tracer('test_shutdown_called_multiple_times')

    result1 = @tracer_provider.shutdown
    result2 = @tracer_provider.shutdown

    assert_equal Instana::Trace::Export::SUCCESS, result1
    assert_equal Instana::Trace::Export::FAILURE, result2

    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
    assert_equal [Instana::Trace::Export::SUCCESS], @tracer_provider.instance_variable_get(:@span_processors).map(&:shutdown)
    assert @tracer_provider.instance_variable_get(:@stopped)
  end

  def test_shutdown_with_zero_timeout
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    # @tracer = @tracer_provider.tracer('test_shutdown_with_zero_timeout')
    timeout = 0
    result = @tracer_provider.shutdown(timeout: timeout)
    assert_equal Instana::Trace::Export::TIMEOUT, result

    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
    assert_equal [Instana::Trace::Export::SUCCESS], @tracer_provider.instance_variable_get(:@span_processors).map(&:shutdown)
    assert @tracer_provider.instance_variable_get(:@stopped)
  end

  def test_force_flush_with_timeout
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    timeout = 10
    result = @tracer_provider.force_flush(timeout: timeout)
    assert_equal Instana::Trace::Export::SUCCESS, result
    @span_processors = @tracer_provider.instance_variable_get(:@span_processors)
    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
    assert_equal [Instana::Trace::Export::SUCCESS], @tracer_provider.instance_variable_get(:@span_processors).map(&:shutdown)
  end

  def test_force_flush_without_timeout
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    result = @tracer_provider.force_flush
    assert_equal Instana::Trace::Export::SUCCESS, result

    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
    assert_equal [Instana::Trace::Export::SUCCESS], @tracer_provider.instance_variable_get(:@span_processors).map(&:shutdown)
  end

  def test_force_flush_with_zero_timeout
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    timeout = 0
    result = @tracer_provider.force_flush(timeout: timeout)
    assert_equal Instana::Trace::Export::TIMEOUT, result

    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
    assert_equal [Instana::Trace::Export::SUCCESS], @tracer_provider.instance_variable_get(:@span_processors).map(&:shutdown)
  end

  def test_add_span_processor_after_shutdown
    @tracer_provider = ::Instana::Trace::TracerProvider.new
    @tracer_provider.add_span_processor(DummyProcessor.new)
    @tracer_provider.shutdown
    result = @tracer_provider.add_span_processor(DummyProcessor.new)
    assert_nil result
    # No new span processor was added as tracer_provider is stopped
    assert_equal 1, @tracer_provider.instance_variable_get(:@span_processors).length
  end

  def test_internal_start_span_untraced
    # An untraced parent context yields a non-recording, level-0 Instana::Span.
    untraced = OpenTelemetry::Common::Utilities.untraced
    span = @tracer_provider.internal_start_span('test_span', :internal, {}, [], Time.now, untraced, nil)

    assert_instance_of Instana::Span, span
    refute span.recording?
    assert_equal 0, span.context.level
    assert_match(/-02\z/, span.context.trace_parent_header)
  end

  def test_internal_start_span_dropped
    span = start_root(dropping_provider)

    assert_instance_of Instana::Span, span
    refute span.recording?
    assert_equal 0, span.context.level
    assert_match(/-02\z/, span.context.trace_parent_header)
  end

  def test_internal_start_span_kept
    span = start_root(keeping_provider)

    assert_instance_of Instana::Span, span
    assert span.recording?
    assert_match(/-03\z/, span.context.trace_parent_header)
  end

  def test_internal_start_span_dropped_preserves_parent
    provider = dropping_provider
    parent = start_root(provider, name: :rack)
    child = Instana::Trace.with_span(parent) { start_root(provider, name: :actioncontroller) }

    assert_equal parent, child.instance_variable_get(:@parent)
  end

  def test_internal_start_span_when_stopped
    provider = keeping_provider
    provider.shutdown
    span = start_root(provider)
    refute span.recording? # stopped forces non-recording even though sampler keeps
  end
end

class DummyProcessor
  def initialize; end

  def shutdown(timeout: nil) # rubocop:disable Lint/UnusedMethodArgument
    Instana::Trace::Export::SUCCESS
  end

  def force_flush(timeout: nil) # rubocop:disable Lint/UnusedMethodArgument
    Instana::Trace::Export::SUCCESS
  end
end
