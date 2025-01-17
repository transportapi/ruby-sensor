# (c) Copyright IBM Corp. 2021
# (c) Copyright Instana Inc. 2016

module Instana
  module Util
    class << self
      ID_RANGE = -2**63..2**63-1
      # Retrieves and returns the source code for any ruby
      # files requested by the UI via the host agent
      #
      # @param file [String] The fully qualified path to a file
      #
      def get_rb_source(file)
        if (file =~ /.rb$/).nil?
          { :error => "Only Ruby source files are allowed. (*.rb)" }
        else
          { :data => File.read(file) }
        end
      rescue => e
        return { :error => e.inspect }
      end

      # Method to collect up process info for snapshots.  This
      # is generally used once per process.
      #
      # :nocov:
      def take_snapshot
        data = {}

        data[:sensorVersion] = ::Instana::VERSION
        data[:ruby_version] = RUBY_VERSION
        data[:rpl] = RUBY_PATCHLEVEL if defined?(RUBY_PATCHLEVEL)

        # Framework Detection
        if defined?(::RailsLts::VERSION)
          data[:framework] = "Rails on Rails LTS-#{::RailsLts::VERSION}"

        elsif defined?(::Rails.version)
          data[:framework] = "Ruby on Rails #{::Rails.version}"

        elsif defined?(::Grape::VERSION)
          data[:framework] = "Grape #{::Grape::VERSION}"

        elsif defined?(::Padrino::VERSION)
          data[:framework] = "Padrino #{::Padrino::VERSION}"

        elsif defined?(::Sinatra::VERSION)
          data[:framework] = "Sinatra #{::Sinatra::VERSION}"
        end

        # Report Bundle
        if defined?(::Gem) && Gem.respond_to?(:loaded_specs)
          data[:versions] = {}

          Gem.loaded_specs.each do |k, v|
            data[:versions][k] = v.version.to_s
          end
        end

        data
      rescue => e
        ::Instana.logger.debug { "#{__method__}:#{File.basename(__FILE__)}:#{__LINE__}: #{e.message}" }
        ::Instana.logger.debug { e.backtrace.join("\r\n") }
        return data
      end
      # :nocov:

      # Best effort to determine a name for the instrumented application
      # on the dashboard.
      #
      # :nocov:
      def get_app_name
        if ENV.key?('INSTANA_SERVICE_NAME')
          return ENV['INSTANA_SERVICE_NAME']
        end

        if defined?(::Resque)
          # Just because Resque is defined doesn't mean this is a resque process necessarily
          # Check arguments for a match
          if ($0 =~ /resque-#{Resque::Version}/)
            return "Resque Worker"
          elsif ($0 =~ /resque-pool-master/)
            return "Resque Pool Master"
          elsif ($0 =~ /resque-scheduler/)
            return "Resque Scheduler"
          end
        end

        if defined?(::RailsLts) || defined?(::Rails)
          return Rails.application.class.to_s.split('::')[0]
        end

        if $0.to_s.empty?
          return "Ruby"
        end

        exe = File.basename($0)
        if exe == "rake"
          return "Rake"
        end

        return exe
      rescue Exception => e
        Instana.logger.info "#{__method__}:#{File.basename(__FILE__)}:#{__LINE__}: #{e.message}"
        Instana.logger.debug { e.backtrace.join("\r\n") }
        return "Ruby"
      end
      # :nocov:

      # Get the current time in milliseconds from the epoch
      #
      # @return [Integer] the current time in milliseconds
      #
      def now_in_ms
        Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond)
      end
      # Prior method name support.  To be deprecated when appropriate.
      alias ts_now now_in_ms

      # Convert a Time value to milliseconds
      #
      # @param time [Time]
      #
      def time_to_ms(time)
        (time.to_f * 1000).floor
      end

      # Generate a random 64bit/128bit ID
      #
      # @param size [Integer] Number of 64 bit integers used to generate the id
      #
      # @return [String] a random 64bit/128bit hex encoded string
      #
      def generate_id(size = 1)
        Array.new(size) { rand(ID_RANGE) }
          .pack('q>*')
          .unpack('H*')
          .first
      end

      # Convert an ID to a value appropriate to pass in a header.
      #
      # @param id [String] the id to be converted
      #
      # @return [String]
      #
      def id_to_header(id)
        return '' unless id.is_a?(String)
        # Only send 64bit IDs downstream for now
        id.length == 32 ? id[16..-1] : id
      end

      # Convert a received header value into a valid ID
      #
      # @param header_id [String] the header value to be converted
      #
      # @return [String]
      #
      def header_to_id(given)
        return '' unless given.is_a?(String)
        return '' unless given.match(/\A[a-z\d]{16,32}\z/i)
        given
      end

      # Get the redis url from redis client.
      # In different versions of Sidekiq different redis clients are used, so getting the redis url should be
      # adapted to the client.
      # - Before version 5 Sidekiq used redis/hiredis
      # - In versions 5 and 6 Sidekiq used resque/redis-namespace
      # - Sidekiq 7 uses redis-rb/redis-client (https://github.com/sidekiq/sidekiq/blob/main/docs/7.0-Upgrade.md#redis-client)
      #
      # @param client [String] the Redis client
      #
      # @return [String, nil]
      #
      def get_redis_url(client)
        case
        when client.respond_to?(:config) # redis-rb/redis-client Redis client
          client.config.server_url
        when client.respond_to?(:connection) # resque/redis-namespace (implemented with redis/redis-rb) Redis client
          "#{client.connection[:host]}:#{client.connection[:port]}"
        when client.respond_to?(:client) && client.client.respond_to?(:options) # redis/hiredis Redis client
          "#{client.client.options[:host]}:#{client.client.options[:port]}"
        else
          nil
        end
      end
    end
  end
end
