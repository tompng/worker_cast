# WorkerCast

```ruby
gem 'worker_cast', github: 'tompng/worker_cast'
```

```ruby
# Listen
ServerList = {
  app1: '10.0.12.34:8000',
  app2: '10.0.12.34:8001',
  backend: '10.0.56.78:8000'
}

WorkerCast.start ServerList, :app1 do |data, respond|
  do_something
  return response
  or
  return :async and call { respond.call response }.asynchronously
end
```

```ruby
# Status

WorkerCast.status
# => { app1: true, app2: true, backend: false }

WorkerCast.status :app2
# => true or false

WorkerCast.status_ok?
# => true(all connected) or false(some not connected)
```

```ruby
# Casting

WorkerCast.broadcast data
# => { app1: 'hi', app2: { 'msg' => 'hello' }, backend: nil(error) }

WorkerCast.broadcast data, response: false
# => { app1: true, app2: true, backend: false }

WorkerCast.broadcast data, include_self: false
# => { app2: 'hi', backend: 'hello' }

WorkerCast.broadcast data, servers: [:app2, :backend]
# => { app2: 'hi', backend: 'hello' }

WorkerCast.send :app2, data
# => response or nil(error)

WorkerCast.send :app2, data, response: false
# => true or false(error)
```

```ruby
# with unicorn(workers >= 2)
Servers = {a1: '10.0.0.1:8000', a2: '10.0.0.1:8001', b1: '10.0.0.2:8000', b2: '10.0.0.2:8001'}
server_group = ENV['SERVER_GROUP']
server_names = [server_group + '1', server_group + '2']
before_fork do
  $server_name = server_names.unshift
end
after_fork do
  WorkerCast.start Servers, $server_name do |data, respond|
    ...
  end
end
```
