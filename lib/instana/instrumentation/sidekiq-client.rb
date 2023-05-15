# (c) Copyright IBM Corp. 2021
# (c) Copyright Instana Inc. 2017

module Instana
  module Instrumentation
    class SidekiqClient
      def call(worker_class, msg, queue, _redis_pool)
        kv_payload = { :'sidekiq-client' => {} }
        kv_payload[:'sidekiq-client'][:queue] = queue
        kv_payload[:'sidekiq-client'][:job] = worker_class.to_s
        kv_payload[:'sidekiq-client'][:retry] = msg['retry'].to_s
        ::Instana.tracer.log_entry(:'sidekiq-client', kv_payload)

        # Temporary until we move connection collection to redis
        # instrumentation
        Sidekiq.redis_pool.with do |client|
          kv_payload[:'sidekiq-client'][:'redis-url'] = Util.get_redis_url(client)
        end

        context = ::Instana.tracer.context
        if context
          msg['X-Instana-T'] = context.trace_id_header
          msg['X-Instana-S'] = context.span_id_header
        end

        result = yield

        kv_payload[:'sidekiq-client'][:job_id] = result['jid']
        result
      rescue => e
        ::Instana.tracer.log_error(e)
        raise
      ensure
        ::Instana.tracer.log_exit(:'sidekiq-client', kv_payload)
      end
    end
  end
end
