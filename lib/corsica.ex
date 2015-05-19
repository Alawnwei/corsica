defmodule Corsica do
  @default_opts [
    origins: "*",
    allow_methods: ~w(HEAD GET POST PUT PATCH DELETE),
    allow_headers: ~w(),
    allow_credentials: false,
  ]

  @moduledoc """
  Plug-based swiss-army knife for CORS requests.

  Corsica provides facilities for dealing with
  [CORS](http://en.wikipedia.org/wiki/Cross-origin_resource_sharing) requests
  and responses. It provides:

    * low-level functions that lets you decide when and where to deal with CORS
      requests and CORS response headers;
    * a plug that handles CORS requests and responds to preflight requests;
    * a router that can be used in your modules in order to turn them into CORS
      handlers which provide fine control for dealing with CORS requests.

  ## How it works

  Corsica is compliant with the [W3C CORS
  specification](http://www.w3.org/TR/cors/). As per this specification, Corsica
  doesn't put any CORS response headers in a connection that holds an invalid
  CORS request. "Invalid CORS request" can mean that a request doesn't have an
  `Origin` hedaer (so it's not a CORS request at all) or that it's a CORS
  request but:

    * the `Origin` request header doesn't match any of the allowed origins
    * the request is a preflight request but it requests to use a method or
      some headers that are not allowed (via the `Access-Control-Request-Method`
      and `Access-Control-Request-Headers` headers)

  When some options that are not mandatory and have no default value (such
  `:max_age`) are not present, the relative header will often not be sent at
  all. This is compliant with the specification and at the same time it reduces
  (even if by a handful of bytes) the size of the request.

  Follows a list of all the *supported* response headers:

    * `Access-Control-Allow-Origin`
    * `Access-Control-Allow-Methods`
    * `Access-Control-Allow-Headers`
    * `Access-Control-Allow-Credentials`
    * `Access-Control-Expose-Headers`
    * `Access-Control-Max-Age`

  ## Using Corsica as a plug

  When `Corsica` is used as a plug, it intercepts all requests; it only sets a
  bunch of CORS headers for regular CORS requests, but it responds (with a 200
  OK and the appropriate headers) to preflight requests.

  If you want to use `Corsica` as a plug, be sure to plug it in your plug
  pipeline **before** any router: routers like `Plug.Router` (or
  `Phoenix.Router`) respond to HTTP verbs as well as request urls, so if
  `Corsica` is plugged after a router then preflight requests (which are
  `OPTIONS` requests) will often result in 404 errors since no route responds to
  an `OPTIONS` request.

      defmodule MyApp.Endpoint do
        plug Head
        plug Corsica, max_age: 600, origins: "*", expose_headers: ~w(X-Foo)
        plug MyApp.Router
      end

  ## Using Corsica as a router generator

  When `Corsica` is used as a plug, it doesn't provide control over which urls
  are CORS-enabled or with which options. In order to do that, you can use
  `Corsica.Router`. See the documentation for `Corsica.Router` for more
  information.

      defmodule MyApp.CORS do
        use Corsica.Router

        @opts [
          max_age: 600,
          allow_credentials: true,
          allow_headers: ~w(X-Secret-Token),
          origins: "*",
        ]

        resource "/public/*", @opts
        resource "/*", Keyword.merge(@opts, origins: "http://foo.com")
      end

      defmodule MyApp.Endpoint do
        plug Logger
        plug MyApp.CORS
        plug MyApp.Router
      end

  ## Origins

  Allowed origins can be specified by passing the `:origins` options either when
  `Corsica` is used or when the `Corsica` plug is plugged to a pipeline.

  `:origins` can be a single value or a list of values. `"*"` can only appear as
  a single value. The default value is `#{inspect @default_opts[:origins]}`.

  Origins can be specified either as:

    * strings - the actual origin and the allowed origin have to be identical
    * regexes - the actual origin has to match the allowed regex
    * functions with a type `(binary -> boolean)` - the function applied to the
      actual origin has to return `true`

  ### The value of the access-control-allow-origin header

  The `:origins` option directly influences the value of the
  `access-control-allow-origin` header. When `:origins` is `"*"`, the
  `access-control-allow-origin` header is set to `*` as well. If the request's
  origin is allowed an `:origins` is something different than `"*"`, then you
  won't see that value as the value of the `access-control-allow-origin` header:
  the value of this header will be the request's origin (which is *mirrored*).
  This behaviour is intentional: it's compliant with the W3C CORS specification
  and at the same time it provides the advantage of "hiding" all the allowed
  origins from the client (which only sees its origin as an allowed origin).

  ## Vary header

  If `:origins` is a list with more than one value and the request origin
  matches, then a `Vary: Origin` header is added to the response.

  ## Options

  Besides `:origins`, the options that can be passed to the `use` macro, to
  `Corsica.DSL.resource/2` and to the `Corsica` plug (along with their default
  values) are:

    * `:allow_headers` - is a list of headers (as binaries). Sets the value of
      the `access-control-allow-headers` header used with preflight requests.
      Defaults to `#{inspect @default_opts[:allow_headers]}` (no headers are
      allowed).
    * `:allow_methods` - is a list of HTTP methods (as binaries). Sets the value
      of the `access-control-allow-methods` header used with preflight requests.
      Defaults to `#{inspect @default_opts[:allow_methods]}`.
    * `:allow_credentials` - is a boolean. If `true`, sends the
      `access-control-allow-credentials` with value `true`. If `false`, prevents
      that header from being sent at all. If `:origins` is set to `"*"` and
      `:allow_credentials` is set to `true`, then the value of the
      `access-control-allow-origin` header will always be the value of the
      `origin` request header (as per the W3C CORS specification) and not `*`.
      Defaults to `#{inspect @default_opts[:allow_credentials]}`.
    * `:expose_headers` - is a list of headers (as binaries). Sets the value of
      the `access-control-expose-headers` response header. This option *does
      not* have a default value; if it's not provided, the
      `access-control-expose-headers` header is not sent at all.
    * `:max_age` - is an integer or a binary. Sets the value of the
      `access-control-max-age` header used with preflight requests. This option
      *does not* have a default value; if it's not provided, the
      `access-control-max-age` header is not sent at all.

  ## Responding to preflight requests

  When the request is a preflight request and a valid one (valid origin, valid
  request method and valid request headers), Corsica directly sends a response
  to that request instead of just adding headers to the connection (so that a
  possible plug pipeline can continue). To do this, Corsica **halts the
  connection** (through `Plug.Conn.halt/1`) and **sends a response**.

  ## Logging

  Corsica supports basic logging functionalities; it can log whether a CORS
  request is a valid one, what CORS headers are added to a response and similar
  information. By default logging is disabled. This can be changed by changing
  the value of the `:log_level` option for the `:corsica` application. For
  example, in `config/config.exs`:

      config :corsica, log_level: :info

  The value of the `:log_level` option is used, as the name implies, as the
  logging level. With the example above, Corsica will log everything at the
  `info` level.

  """

  # Here are some nice (and apparently overlooked!) quotes from the W3C CORS
  # specification, along with some thoughts around them.
  #
  # http://www.w3.org/TR/cors/#access-control-allow-credentials-response-header
  # The syntax of the Access-Control-Allow-Credentials header only accepts the
  # value "true" (without quotes, case-sensitive). Any other value is not
  # conforming to the official CORS specification (many libraries tend to just
  # shove the value of a boolean in that header, so it happens to have the value
  # "false" as well).
  #
  # http://www.w3.org/TR/cors/#resource-requests, item 3.
  # > The string "*" cannot be used [as the value for the
  # > Access-Control-Allow-Origin] header for a resource that supports
  # > credentials.
  #
  # http://www.w3.org/TR/cors/#resource-implementation
  # > [...] [authors] should send a Vary: Origin HTTP header or provide other
  # > appropriate control directives to prevent caching of such responses, which
  # > may be inaccurate if re-used across-origins.
  #
  # http://www.w3.org/TR/cors/#resource-preflight-requests, item 9.
  # > If method is a simple method, [setting the Access-Control-Allow-Methods
  # > header] may be skipped (but it is not prohibited).
  # > Simply returning the method indicated by Access-Control-Request-Method (if
  # > supported) can be enough.
  # However, this behaviour can inhibit caching from the client side since the
  # client has to issue a preflight request for each method it wants to use,
  # while if all the allowed methods are returned every time then the cached
  # preflight request can be used more times.
  #
  # http://www.w3.org/TR/cors/#resource-preflight-requests, item 10.
  # > If each of the header field names is a simple header and none is
  # > Content-Type, [setting the Access-Control-Allow-Headers] may be
  # > skipped. Simply returning supported headers from
  # > Access-Control-Allow-Headers can be enough.
  # The same argument for Access-Control-Allow-Methods can be made here.

  import Plug.Conn
  alias Plug.Conn

  require Logger

  @behaviour Plug

  @log_level Application.get_env(:corsica, :log_level, false)

  defmacrop log(msg) do
    if @log_level do
      quote do
        msg = "[Corsica] " <> unquote(msg)
        Logger.unquote(@log_level)(msg)
      end
    end
  end

  # Plug callbacks.

  def init(opts) do
    sanitize_opts(opts)
  end

  def call(%Conn{} = conn, opts) do
    cond do
      not cors_req?(conn)      -> conn
      not preflight_req?(conn) -> put_cors_simple_resp_headers(conn, opts)
      true                     -> send_preflight_resp(conn, opts)
    end
  end

  # Public so that it can be called from `Corsica.Router` (and for testing too).
  @doc false
  def sanitize_opts(opts) do
    import Enum, only: [map: 2]
    opts = Keyword.merge(@default_opts, opts)

    if opts[:max_age] do
      opts = Keyword.update!(opts, :max_age, &to_string/1)
    end

    if opts[:expose_headers] do
      opts = Keyword.update!(opts, :expose_headers, &Enum.join(&1, ", "))
    end

    opts
    |> Keyword.update!(:allow_methods, fn(m) -> map(m, &String.upcase/1) end)
    |> Keyword.update!(:allow_headers, fn(h) -> map(h, &String.downcase/1) end)
  end

  # Utilities

  @doc """
  Checks whether a given connection holds a CORS request.

  This function doesn't check if the CORS request is a *valid* CORS request: it
  just checks that it's a CORS request, that is, it has an `Origin` request
  header.
  """
  @spec cors_req?(Conn.t) :: boolean
  def cors_req?(%Conn{} = conn), do: get_req_header(conn, "origin") != []

  @doc """
  Checks whether a given connection holds a preflight CORS request.

  This function doesn't check that the preflight request is a *valid* CORS
  request: it just checks that it's a preflight request. A request is considered
  to be a CORS preflight request if and only if its request method is `OPTIONS`
  and it has a `Access-Control-Request-Method` request header.

  Note that if a request is a valid preflight request, that makes it a valid
  CORS request as well. You can thus call just `preflight_req?/1` instead of
  `preflight_req?/1` and `cors_req?/1`.
  """
  @spec preflight_req?(Conn.t) :: boolean
  def preflight_req?(%Conn{method: "OPTIONS"} = conn),
    do: cors_req?(conn) and get_req_header(conn, "access-control-request-method") != []
  def preflight_req?(%Conn{}),
    do: false

  # Request handling

  @doc """
  Sends a CORS preflight response regardless of the request being a valid CORS
  request or not.

  This function assumes nothing about `conn`. If it's a valid CORS preflight
  request with an allowed origin, CORS headers are set by calling
  `put_cors_preflight_resp_headers/2` and the response **is sent** with status
  `status` and body `body`. `conn` is **halted** before being sent.

  The response is always sent because if the request is not a valid CORS
  request, then no CORS headers will be added to the response. This behaviour
  will be interpreted by the browser as a non-allowed preflight request, as
  expected.

  For more information on what headers are sent with the response if the
  preflight request is valid, look at the documentation for
  `put_cors_preflight_resp_headers/2`.

  ## Examples

      defmodule MyRouter do
        use Plug.Router
        plug :match
        plug :dispatch

        options "/foo", do: Corsica.send_preflight_resp(conn, @cors_opts)
        get "/foo", do: send_resp(conn, 200, "ok")
      end

  """
  @spec send_preflight_resp(Conn.t, 100..599, binary, Keyword.t) :: Conn.t
  def send_preflight_resp(%Conn{} = conn, status \\ 200, body \\ "", opts) do
    conn
    |> put_cors_preflight_resp_headers(opts)
    |> halt
    |> send_resp(status, body)
  end

  @doc """
  Adds CORS response headers to a simple CORS request to `conn`.

  This function assumes nothing about `conn`. If `conn` holds an invalid CORS
  request or a request whose origin is not allowed, `conn` is returned
  unchanged; the absence of CORS headers will be interpreted as an invalid CORS
  response by the browser.

  If the CORS request is valid, the following response headers are always set:

    * `Access-Control-Allow-Origin`

  and the following headers are optionally set (if the corresponding option is
  present):

    * `Access-Control-Expose-Headers`
    * `Access-Control-Allow-Credentials`

  ## Examples

      put_cors_simple_resp_headers(conn, origins: "*", allow_credentials: true)

  """
  @spec put_cors_simple_resp_headers(Conn.t, Keyword.t) :: Conn.t
  def put_cors_simple_resp_headers(%Conn{} = conn, opts) do
    opts = sanitize_opts(opts)
    if cors_req?(conn) && allowed_origin?(conn, opts) do
      log "Origin '#{origin(conn)}' allowed, adding access-control-* headers"
      conn
      |> put_common_headers(opts)
      |> put_expose_headers_header(opts)
    else
      log "Origin '#{origin(conn)}' not allowed, no access-control-* headers being set"
      conn
    end
  end

  @doc """
  Adds CORS response headers to a preflight request to `conn`.

  This function assumes nothing about `conn`. If `conn` holds an invalid CORS
  request or an invalid preflight request, then `conn` is returned unchanged;
  the absence of CORS headers will be interpreted as an invalid CORS response by
  the browser.

  If the request is a valid one, the following headers will always be added to
  the response:

    * `Access-Control-Allow-Origin`
    * `Access-Control-Allow-Methods`
    * `Access-Control-Allow-Headers`

  and the following headers will optionally be added (based on the value of the
  corresponding options):

    * `Access-Control-Allow-Credentials`
    * `Access-Control-Max-Age`

  ## Examples

      put_cors_preflight_resp_headers conn, [
        max_age: 86400,
        allow_headers: ~w(X-Header),
        origins: ~r/\w+\.foo\.com$/
      ]

  """
  @spec put_cors_preflight_resp_headers(Conn.t, Keyword.t) :: Conn.t
  def put_cors_preflight_resp_headers(%Conn{} = conn, opts) do
    opts = sanitize_opts(opts)

    if allowed_origin?(conn, opts) and preflight_req?(conn) and allowed_preflight?(conn, opts) do
      log "Allowed preflight request from origin '#{origin(conn)}', adding access-control-* headers"
      conn
      |> put_common_headers(opts)
      |> put_allow_methods_header(opts)
      |> put_allow_headers_header(opts)
      |> put_max_age_header(opts)
    else
      log "Request is not a valid CORS preflight request, no access-control-* headers being added"
      conn
    end
  end

  defp put_common_headers(conn, opts) do
    conn
    |> put_allow_credentials_header(opts)
    |> put_allow_origin_header(opts)
    |> update_vary_header(opts[:origins])
  end

  defp put_allow_credentials_header(conn, opts) do
    if opts[:allow_credentials] do
      put_resp_header(conn, "access-control-allow-credentials", "true")
    else
      conn
    end
  end

  defp put_allow_origin_header(conn, opts) do
    actual_origin   = conn |> get_req_header("origin") |> hd
    allowed_origins = Keyword.fetch!(opts, :origins)

    # '*' cannot be used as the value of the `Access-Control-Allow-Origins`
    # header if `Access-Control-Allow-Credentials` is true.
    value =
      if allowed_origins == "*" and not opts[:allow_credentials] do
        "*"
      else
        actual_origin
      end

    put_resp_header(conn, "access-control-allow-origin", value)
  end

  # Only update the Vary header if the origin is not a binary (it could be a
  # regex or a function) or if there's a list of more than one origins.
  defp update_vary_header(conn, origin) when is_binary(origin),
    do: conn
  defp update_vary_header(conn, [origin]) when is_binary(origin),
    do: conn
  defp update_vary_header(conn, _origin),
    do: update_in(conn.resp_headers, &[{"vary", "origin"}|&1])

  defp put_allow_methods_header(conn, opts) do
    value = opts |> Keyword.fetch!(:allow_methods) |> Enum.join(", ")
    put_resp_header(conn, "access-control-allow-methods", value)
  end

  defp put_allow_headers_header(conn, opts) do
    value = opts |> Keyword.fetch!(:allow_headers) |> Enum.join(", ")
    put_resp_header(conn, "access-control-allow-headers", value)
  end

  defp put_max_age_header(conn, opts) do
    if max_age = opts[:max_age] do
      put_resp_header(conn, "access-control-max-age", max_age)
    else
      conn
    end
  end

  defp put_expose_headers_header(conn, opts) do
    expose_headers = opts[:expose_headers]
    if expose_headers && expose_headers != "" do
      put_resp_header(conn, "access-control-expose-headers", expose_headers)
    else
      conn
    end
  end

  defp origin(conn) do
    case get_req_header(conn, "origin") do
      []         -> nil
      [origin|_] -> origin
    end
  end

  # Made public for testing
  @doc false
  def allowed_origin?(conn, opts) do
    [origin|_] = get_req_header(conn, "origin")
    do_allowed_origin?(opts[:origins], origin)
  end

  defp do_allowed_origin?("*", _origin),
    do: true
  defp do_allowed_origin?(allowed_origins, origin)
    when is_list(allowed_origins),
    do: Enum.any?(allowed_origins, &matching_origin?(&1, origin))
  defp do_allowed_origin?(allowed_origin, origin),
    do: matching_origin?(allowed_origin, origin)

  defp matching_origin?(origin, origin),
    do: true
  defp matching_origin?(allowed, _actual) when is_binary(allowed),
    do: false
  defp matching_origin?(allowed, actual) when is_function(allowed),
    do: allowed.(actual)
  defp matching_origin?(allowed, actual),
    do: Regex.match?(allowed, actual)

  # Made public for testing.
  @doc false
  def allowed_preflight?(conn, opts) do
    opts = sanitize_opts(opts)
    allowed_request_method?(conn, opts[:allow_methods]) and
      allowed_request_headers?(conn, opts[:allow_headers])
  end

  defp allowed_request_method?(conn, allowed_methods) do
    # We can safely assume there's an Access-Control-Request-Method header
    # otherwise the request wouldn't have been identified as a preflight
    # request.
    req_method = conn |> get_req_header("access-control-request-method") |> hd
    req_method in allowed_methods
  end

  defp allowed_request_headers?(conn, allowed_headers) do
    # If there is no Access-Control-Request-Headers header, this will all amount
    # to an empty list for which `Enum.all?/2` will return `true`.
    conn
    |> get_req_header("access-control-request-headers")
    |> Enum.flat_map(&Plug.Conn.Utils.list/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.all?(&(&1 in allowed_headers))
  end
end
