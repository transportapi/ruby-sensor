require 'test_helper'
require 'active_record'

class ActiveRecordPgTest < Minitest::Test
  def setup
     ActiveRecord::Base.establish_connection(
       adapter:  "postgresql",
       host:     ENV['TRAVIS_PSQL_HOST'],
       username: "postgres",
       password: ENV['TRAVIS_PSQL_PASS'],
       database: "travis_ci_test"
     )
  end

  def test_config_defaults
    assert ::Instana.config[:active_record].is_a?(Hash)
    assert ::Instana.config[:active_record].key?(:enabled)
    assert_equal true, ::Instana.config[:active_record][:enabled]
  end

  def test_lookup
    clear_all!

    Net::HTTP.get(URI.parse('http://localhost:3205/test/db'))

    traces = Instana.processor.queued_traces
    assert_equal 1, traces.count
    trace = traces.first

    # Excon validation
    assert_equal 4, trace.spans.count
    spans = trace.spans.to_a
    first_span = spans[0]
    second_span = spans[1]
    third_span = spans[2]
    fourth_span = spans[3]

    assert_equal :rack, first_span.name
    assert_equal :activerecord, second_span.name
    assert_equal :activerecord, third_span.name
    assert_equal :activerecord, fourth_span.name

    assert_equal "INSERT INTO \"blocks\" (\"name\", \"color\", \"created_at\", \"updated_at\") VALUES ($1, $2, $3, $4) RETURNING \"id\"", second_span[:data][:activerecord][:sql]
    assert_equal "SELECT  \"blocks\".* FROM \"blocks\" WHERE \"blocks\".\"name\" = $1 ORDER BY \"blocks\".\"id\" ASC LIMIT $2", third_span[:data][:activerecord][:sql]
    assert_equal "DELETE FROM \"blocks\" WHERE \"blocks\".\"id\" = $1", fourth_span[:data][:activerecord][:sql]

    assert_equal "postgresql", second_span[:data][:activerecord][:adapter]
    assert_equal "postgresql", third_span[:data][:activerecord][:adapter]
    assert_equal "postgresql", fourth_span[:data][:activerecord][:adapter]

    assert_equal ENV['TRAVIS_PSQL_HOST'], second_span[:data][:activerecord][:host]
    assert_equal ENV['TRAVIS_PSQL_HOST'], third_span[:data][:activerecord][:host]
    assert_equal ENV['TRAVIS_PSQL_HOST'], fourth_span[:data][:activerecord][:host]

    assert_equal "postgres", second_span[:data][:activerecord][:username]
    assert_equal "postgres", third_span[:data][:activerecord][:username]
    assert_equal "postgres", fourth_span[:data][:activerecord][:username]
  end
end
