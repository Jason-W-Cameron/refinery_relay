# frozen_string_literal: true

require "redis"
require "socket"

module RedisTestServer
  private

  def start_test_redis
    configured_url = ENV["REDIS_URL"].presence
    if configured_url
      begin
        configured_redis = Redis.new(url: configured_url)
        return @test_redis = configured_redis if configured_redis.ping == "PONG"
      rescue Redis::CannotConnectError
        configured_redis&.close
      end
    end

    executable = redis_server_executable
    raise "redis-server is required for Relay integration tests" unless executable

    port = available_tcp_port
    @redis_server_pid = Process.spawn(
      executable,
      "--bind", "127.0.0.1",
      "--port", port.to_s,
      "--save", "",
      "--appendonly", "no",
      out: File::NULL,
      err: File::NULL
    )
    @test_redis = Redis.new(url: "redis://127.0.0.1:#{port}/15")
    wait_for_redis!
    @test_redis
  end

  def stop_test_redis
    @test_redis&.flushdb
    @test_redis&.close
    return unless @redis_server_pid

    Process.kill("TERM", @redis_server_pid)
    Process.wait(@redis_server_pid)
  rescue Errno::ESRCH, Errno::ECHILD, Redis::BaseError
    nil
  ensure
    @test_redis = nil
    @redis_server_pid = nil
  end

  def redis_server_executable
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).filter_map do |directory|
      candidate = File.join(directory, "redis-server")
      candidate if File.file?(candidate) && File.executable?(candidate)
    end.first
  end

  def available_tcp_port
    server = TCPServer.new("127.0.0.1", 0)
    server.local_address.ip_port
  ensure
    server&.close
  end

  def wait_for_redis!
    50.times do
      return if @test_redis.ping == "PONG"
    rescue Redis::CannotConnectError
      sleep 0.02
    end
    raise "redis-server did not become ready"
  end
end
