# RestEasy Authentication Architecture

## Overview

Authentication is handled by pluggable auth modules — any object that responds
to four lifecycle methods. The gem manages the orchestration (when to call what),
the auth module manages its own domain (credentials, expiry, persistence,
retry logic).

## Configuration

Auth is configured at the module level, not per resource. The entire API gem
shares one auth module instance.

```ruby
module Fortnox
  extend RestEasy

  configure do |config|
    config.base_url = "https://api.fortnox.se/3"
    config.authentication = MachineKeyAuth.new(api_key: ENV['FORTNOX_KEY'])
    config.max_retries = 3
  end

  # Transport-level concerns (mTLS, custom middleware, etc.)
  connection do |conn|
    conn.ssl.client_cert = OpenSSL::X509::Certificate.new(...)
  end
end
```

## Auth Module Contract

Any object responding to these four methods:

### `acquire(config)`

Called to obtain credentials. This could mean reading a static key, exchanging
client credentials for a token, refreshing an expired token, or anything else
the scheme requires.

Persistence is entirely the auth module's responsibility. It may store
credentials in memory, Redis, a file, a database — whatever fits the use case.
The gem makes no assumptions.

```ruby
def acquire(config)
  { api_key: config.api_key }
end
```

### `apply(credentials, request)`

Called before every HTTP request. Receives the credentials returned by `acquire`
and the full Faraday request object. Modifies the request to include
authentication (headers, query params, etc.).

Since it receives the full Faraday request, it has access to headers, body,
method, and URL — sufficient for even signing-based schemes like HMAC/AWS
Signature V4.

```ruby
def apply(credentials, request)
  request.headers['Authorization'] = "Bearer #{credentials[:token]}"
end
```

### `expired?(credentials)`

Called before each request to check if credentials need re-acquisition. Since
this is only checked at call time, there is no guarantee that credentials won't
expire between the check and the actual request — `on_rejected` handles that
case.

```ruby
def expired?(credentials)
  Time.now >= credentials[:expires_at]
end
```

### `on_rejected(credentials, response)`

Called when a request fails. The auth module decides what to do based on the
response. It understands its own API's error semantics — what a 401 vs 429 vs
503 means in context.

- **Return normally** — the gem retries the request (up to the module's
  configured max retry count).
- **Raise** — the gem propagates the error to the caller.

The auth module handles the *what* and *how long* (sleeping, backoff,
re-acquisition). The gem handles *how many times* (max retries, configured on
the module).

```ruby
def on_rejected(credentials, response)
  case response.status
  when 401
    acquire(config)  # refresh credentials before retry
  when 429
    wait = response.headers['Retry-After']&.to_i || 30
    raise RestEasy::RateLimitError if wait > config.max_retry_wait
    sleep(wait)
  when 500, 502, 503
    sleep(@backoff_count * 2)
    @backoff_count += 1
  else
    raise RestEasy::RequestError, response
  end
end
```

## Request Lifecycle

1. Check `expired?(credentials)` — if true, call `acquire(config)`
2. Call `apply(credentials, request)` to attach credentials to request
3. Make the HTTP request
4. If request fails, call `on_rejected(credentials, response)`
   - If `on_rejected` returns normally, retry from step 1 (up to max retries)
   - If `on_rejected` raises, propagate the error

## Null Auth

The gem provides a default no-op auth module for APIs that don't require
authentication, or when authentication is handled at the transport level
(e.g. mutual TLS configured on the Faraday connection).

## Transport-Level Concerns

Things like mutual TLS are not authentication in this model — they are transport
configuration. The module's `connection` block yields the Faraday connection
object, which is the appropriate place to configure SSL contexts, client
certificates, etc.

```ruby
module Fortnox
  extend RestEasy

  connection do |conn|
    conn.ssl.client_cert = OpenSSL::X509::Certificate.new(...)
    conn.ssl.client_key = OpenSSL::PKey::RSA.new(...)
  end
end
```

## Built-In Auth Modules

The gem ships with implementations for the most common schemes:

- **Null** — no-op, for unauthenticated APIs or transport-level auth
- **PSK / API Key** — static key applied as a header
- **Basic Auth** — username:password base64-encoded
- **OAuth2 (client credentials)** — token acquisition and refresh

Custom schemes are written by implementing the four-method contract.

## Example: Full Custom Auth Module

```ruby
class FortnoxAuth
  def initialize
    @backoff_count = 0
  end

  def acquire(config)
    token = SomeTokenService.exchange(
      client_id: config.client_id,
      client_secret: config.client_secret
    )
    @backoff_count = 0
    {
      token: token.access_token,
      expires_at: Time.now + token.expires_in
    }
  end

  def apply(credentials, request)
    request.headers['Authorization'] = "Bearer #{credentials[:token]}"
    request.headers['Client-Secret'] = credentials[:client_secret]
  end

  def expired?(credentials)
    Time.now >= credentials[:expires_at]
  end

  def on_rejected(credentials, response)
    case response.status
    when 401
      acquire(@config)
    when 429
      wait = response.headers['Retry-After']&.to_i || 60
      raise RestEasy::RateLimitError, "Rate limited for #{wait}s" if wait > 300
      sleep(wait)
    when 500, 502, 503
      raise RestEasy::RemoteServerError if @backoff_count > 5
      sleep(@backoff_count * 2)
      @backoff_count += 1
    else
      raise RestEasy::RequestError, "Request failed: #{response.status}"
    end
  end
end
```
