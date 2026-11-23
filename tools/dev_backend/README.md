# dev_backend

An in-memory backend that speaks the mobile_tasks contract, for running the
app in the simulator without a real server (chapter 35). A development tool:
never a dependency of another package, never in production.

```sh
# from the workspace root
dart run tools/dev_backend/bin/dev_backend.dart [--port 8080] [--token-minutes 15] [--control-port 8081]
```

- Listens only on `127.0.0.1`. Accounts, sessions, and tasks live in memory:
  stopping the process erases everything, and the app goes back to the
  sign-in on the next refresh.
- Each request shows up on one line (method, path, and status), with no body
  and no token.
- In the server's terminal, `stop` closes the port without losing the state
  (the app sees refused connections, like a backend that is down) and
  `start` opens it again.
- With `--control-port 8081`, the same two actions arrive over HTTP, on a
  separate port that stays open when the API port closes (chapter 39):
  `POST /control/stop`, `POST /control/start`, and `GET /control/status`,
  which answer `{"open": true|false}`. That is how the integration tests,
  running on the device, take the backend down.

## The contract

| Route | What it does |
| --- | --- |
| `GET`/`HEAD /v1/health` | 200, no authentication |
| `POST /v1/auth/register` | 201 with user and tokens; 422 `email_already_registered` or `weak_password` |
| `POST /v1/auth/sign-in` | 200 with user and tokens; 401 `invalid_credentials` |
| `POST /v1/auth/refresh` | swaps both tokens; 401 `invalid_refresh_token` |
| `POST /v1/auth/sign-out` | 204; the token stops being valid |
| `GET /v1/tasks?status=active&limit=&cursor=` | the user's unarchived tasks, oldest first, by cursor |
| `GET /v1/tasks/{id}` | the task; 404 if it does not exist |
| `PUT /v1/tasks/{id}` | creates with the app's id (201, version 1); the same operation again returns the task; another operation on the same id is 409 `version_conflict` |
| `PATCH /v1/tasks/{id}` | changes or archives with `baseVersion`; a different version is 409 `version_conflict`; an operation already applied returns the task; 404 if it does not exist |

Every task route requires `Authorization: Bearer`; an expired token gets 401.
An `Idempotency-Key` with the same body gets the stored response, and with a
different body, 422 `idempotency_key_reused`. Titles follow the `TaskTitle`
rule: leading and trailing spaces removed, from 1 to 200 code points.

## "Someone else"

| Route | To trigger |
| --- | --- |
| `POST /dev/tasks/{id}/edit` with `{"title"?, "status"?}` | a version conflict |
| `DELETE /dev/tasks/{id}` | a task deleted on the server |
| `POST /dev/reject-next` with `{"status"?, "code"?}` | a rejection that is not a conflict (422 by default) |
| `POST /dev/omit-version-next` | an accepted response without the version: the non-fatal `tasks outbox response` error in Crashlytics (chapter 38) |
| `POST /dev/expire-tokens` | the token refresh |
| `GET /dev/state`, `POST /dev/reset` | view or clear the state |

Task ids are the UUIDs the app generated: get them from `GET /dev/state` and
paste them in place of `{id}`. An id that does not exist, such as the word
`ID` pasted by mistake, gets 404, and nothing changes on the server.

## Tests

`test/dev_backend_handler_test.dart` calls the handler directly, one rule per
test. `test/control_test.dart` closes and opens the API port through the
control port and checks the refused connection and the preserved state.
`test/contract_test.dart` starts the server on a free port and reads it with
the app packages' `HttpApiClient`, `AuthModel`, `RestAuthTokenService`, and
`RestTaskService`: if the backend drifts from what the app reads, the test
breaks before the simulator does.
