# frozen_string_literal: true

require "json"
require "socket"

class RelayStubServer
  attr_reader :requests

  def initialize
    @server = TCPServer.new("127.0.0.1", 0)
    @requests = Queue.new
  end

  def base_url
    "http://127.0.0.1:#{@server.local_address.ip_port}"
  end

  def start
    @thread = Thread.new do
      loop { handle(@server.accept) }
    rescue IOError, Errno::EBADF
      nil
    end
    self
  end

  def stop
    @server.close
    @thread&.join(1)
  end

  def next_request
    requests.pop
  end

  private

  def handle(socket)
    request_line = socket.gets.to_s
    method, path = request_line.split
    headers = read_headers(socket)
    body = socket.read(headers.fetch("content-length", "0").to_i)
    requests << {
      method: method,
      path: path,
      headers: headers,
      body: body.presence && JSON.parse(body)
    }

    if method == "GET" && path == "/source"
      respond(socket, "text/html", <<~HTML)
        <html><head><meta property="og:image" content="#{base_url}/source.jpg"></head></html>
      HTML
    else
      respond(socket, "application/json", chat_payload.to_json)
    end
  rescue JSON::ParserError
    respond(socket, "application/json", { error: "invalid_json" }.to_json, status: "400 Bad Request")
  ensure
    socket.close
  end

  def read_headers(socket)
    {}.tap do |headers|
      while (line = socket.gets)
        break if line == "\r\n"

        name, value = line.split(":", 2)
        headers[name.downcase] = value.to_s.strip
      end
    end
  end

  def respond(socket, content_type, body, status: "200 OK")
    socket.write <<~HTTP.gsub("\n", "\r\n")
      HTTP/1.1 #{status}
      Content-Type: #{content_type}
      Content-Length: #{body.bytesize}
      Connection: close

      #{body}
    HTTP
  end

  def chat_payload
    {
      conversation_id: "conversation-system-test",
      answer: "Relay can answer from the published website [1]",
      citations: [
        {
          title: "Published information",
          url: "#{base_url}/source",
          content_type: "page"
        }
      ],
      uploaded_sources: []
    }
  end
end
