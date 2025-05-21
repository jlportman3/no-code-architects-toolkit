# Repository Guidelines

This project contains the No-Code Architects Toolkit API implemented in Python and packaged with Docker.

## Development
- Ensure basic Python syntax checks pass before committing:
  ```bash
  python -m py_compile $(git ls-files '*.py')
  ```
- The Docker image for `ncat` is built locally; running `docker compose pull` will fail. Use `docker compose build` to build images.

## Docker
- `docker-compose.yml` defines two services: `ncat` and `minio`.
- Start services with:
  ```bash
  docker compose up -d
  ```

## Environment
- Copy `.env.sample` to `.env` and adjust values for local development.


