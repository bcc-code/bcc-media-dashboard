# BCC Media dashboard

A simple operations dashboard to see important statuses.

## Running locally

```sh
mix setup
mix phx.server
```

Then open <http://localhost:4000>.

## Deployment

Built as a Docker image, configured at runtime via environment variables.

### Build

```sh
docker build -t bccm-dashboard .
```

### Run

```sh
docker run -p 4000:4000 \
  -e SECRET_KEY_BASE="$(mix phx.gen.secret)" \
  -e PHX_HOST=dashboard.example.com \
  -e SEMAPHORE_TOKEN=... \
  bccm-dashboard
```

### Environment variables

| Variable                  | Default       | Notes                                                                                |
| ------------------------- | ------------- | ------------------------------------------------------------------------------------ |
| `SECRET_KEY_BASE`         | —             | **Required in prod.** Generate with `mix phx.gen.secret`. Used to sign sessions.     |
| `PHX_HOST`                | `example.com` | Public hostname; used for URL generation. Set this for any real deploy.              |
| `PORT`                    | `4000`        | HTTP port the app listens on.                                                        |
| `SEMAPHORE_TOKEN`         | —             | API token for the Semaphore CI integration. Without it, the section shows an error.  |
| `SEMAPHORE_ORG`           | `bccmedia`    | Semaphore organization slug.                                                         |
| `SEMAPHORE_REFRESH_MS`    | `60000`       | Poll interval in milliseconds.                                                       |
| `SEMAPHORE_WINDOW_DAYS`   | `7`           | Days of pipeline history to fetch.                                                   |
| `SEMAPHORE_MAX_PROJECTS`  | `12`          | Max projects to display.                                                             |
| `SEMAPHORE_MAX_PIPELINES` | `16`          | Max pipeline dots per project.                                                       |
| `DNS_CLUSTER_QUERY`       | —             | DNS query for `DNSCluster` (only set if clustering nodes).                           |

If `SEMAPHORE_TOKEN` is missing or invalid, the dashboard still renders and the Semaphore section surfaces the fetch error instead — useful while bootstrapping the deploy.
