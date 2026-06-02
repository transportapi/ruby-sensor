# frozen_string_literal: true

# (c) Copyright IBM Corp. 2021
# (c) Copyright Instana Inc. 2021

# Minimal OpenTelemetry-shaped samplers for exercising TracerProvider's
# recording vs non-recording branches deterministically, without depending on
# the host application's Tracing::HeadSampler.

module Instana
  module TestSupport
    # A sampler whose decision is fixed at construction.
    class FixedSampler
      Result = Struct.new(:sampled, :recording, :tracestate, :attributes) do
        def sampled?
          sampled
        end

        def recording?
          recording
        end
      end

      def initialize(sampled:)
        @sampled = sampled
      end

      def should_sample?(trace_id:, parent_context:, links:, name:, kind:, attributes:) # rubocop:disable Lint/UnusedMethodArgument, Metrics/ParameterLists
        Result.new(@sampled, @sampled, OpenTelemetry::Trace::Tracestate::DEFAULT, {})
      end

      def description
        "Instana::TestSupport::FixedSampler(sampled=#{@sampled})"
      end
    end

    # Always drops (non-recording).
    def self.dropping_sampler
      FixedSampler.new(sampled: false)
    end

    # Always keeps (recording).
    def self.keeping_sampler
      FixedSampler.new(sampled: true)
    end
  end
end
