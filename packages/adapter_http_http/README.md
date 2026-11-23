# adapter_http_http

The project's HTTP access, with the Dart team's `http` package. It replaced
`adapter_http_dio` in chapter 41.

- **Contains:** `HttpApiClient` (`ApiClient` port), with the token and the
  refresh on a 401 within the send itself, retries through the package's
  `RetryClient`, and each attempt's log and timeout; and
  `HttpReachabilityProbe` (`ReachabilityProbe` port).
- **Never contains:** a module's endpoints, models, or rules, or the get_it
  registration (the host builds it). No type from the http package leaves
  this package: every failure becomes `ApiError`.
