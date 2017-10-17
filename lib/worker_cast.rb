require "worker_cast/version"
require 'socket'
require 'json'

class WorkerCast::Connection
  def initialize name, ip, port
    @name = name
    @ip = ip
    @port = port
    @send_queue = Queue.new
    @serial_key = 0
    @mutex = Mutex.new
    @waitings = {}
    Thread.new do
      loop do
        start rescue nil
        sleep 1
      end
    end
    Thread.new do
      send_loop
    end
  end

  def send_loop
    loop do
      data = @send_queue.deq
      begin
        @socket.puts data.to_json
      rescue StandardError
        key = data[1]
        @mutex.synchronize { @waitings.delete(key) << nil } if key
      end
    end
  end

  def send(message, response_queue = nil)
    unless @socket
      response_queue&.<< nil
      return false
    end
    if response_queue
      @mutex.synchronize do
        key = @serial_key += 1
        @waitings[key] = response_queue
        @send_queue << [message, key]
      end
    else
      @send_queue << [message]
    end
    true
  end

  def start
    @socket = TCPSocket.new(@ip, @port)
    while (data = @socket.gets)
      message, key = JSON.parse(data)
      @mutex.synchronize do
        @waitings.delete(key) << message rescue nil
      end
    end
  ensure
    @socket.close
    @socket = nil
    @mutex.synchronize do
      @waitings.each_value { |queue| queue << nil rescue nil }
      @waitings = {}
    end
  end
end

module WorkerCast
  def self.start(servers, self_name, &block)
    self_ip, self_port = servers[self_name].split ':'
    @servers = {}
    @server_name = self_name
    @block = block
    @ondata_queue = Queue.new
    servers.each do |name, ip_port|
      ip, port = ip_port.split ':'
      ip = 'localhost' if ip == self_ip
      @servers[name] = Connection.new name, ip, port
    end
    Thread.new { accept_start self_port }
    Thread.new { consume }
  end

  def self.server_name
    @server_name
  end

  def self.broadcast message, response: true
    if response
      name_queues = @servers.map do |name, server|
        queue = Queue.new
        server.send message, queue
        [name, queue]
      end
      name_queues.map { |name, queue| [name, queue.deq] }.to_h
    else
      @servers.map do |name, server|
        [name, server.send(message)]
      end.to_h
    end
  end

  def self.send name, message, response: true
    server = @servers[name]
    raise "server undefined: #{name}" unless server
    if response
      queue = Queue.new
      server.send message, queue
      queue.deq
    else
      server.send message
    end
  end

  def self.consume
    loop do
      message, key, response_queue = @ondata_queue.deq
      respond = lambda do |response|
        response_queue << [response, key] rescue nil if key
        key = nil
      end
      response = @block.call message, respond rescue nil
      respond.call response unless response == :async
    end
  end

  def self.accept_start port
    server = TCPServer.new port
    loop do
      onconnect server.accept
    end
  end

  def self.ondata message_key_queue
    @ondata_queue << message_key_queue
  end

  def self.onconnect socket
    response_queue = Queue.new
    Thread.new do
      begin
        while (data = socket.gets)
          message, key = JSON.parse data
          ondata [message, key, response_queue]
        end
      ensure
        response_queue.close
        socket.close
      end
    end
    Thread.new do
      begin
        while (data = response_queue.deq)
          socket.puts data.to_json
        end
      ensure
        response_queue.close
        socket.close
      end
    end
  end
end
