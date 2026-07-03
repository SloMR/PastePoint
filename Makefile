# Simple makefile for managing Docker Compose environments
# Usage: make prod | make dev | make down

.PHONY: dev prod down stop logs certs help

# Export BuildKit for better caching and parallel builds
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Env file used by read-only targets (logs/down/stop). Auto-detects whichever
# file exists; prefers .env.development on dev machines that have both.
# Override explicitly: `make logs ENV_FILE=.env.production`
ENV_FILE ?= $(firstword $(wildcard .env.development .env.production))

# Production environment (default)
prod:
	@echo "Starting production environment..."
	@test -f .env.production || (echo "Error: .env.production not found. Copy .env.production.example to .env.production on this host and fill in real values." && exit 1)
	docker compose --env-file .env.production build
	docker compose --env-file .env.production up --force-recreate -d
	@echo "Production services are starting. View logs with: make logs"

# Development environment
dev:
	@echo "Starting development environment..."
	@test -f .env.development || (echo "Error: .env.development not found. Copy .env.development.example to .env.development and configure it." && exit 1)
	docker compose --env-file .env.development build
	docker compose --env-file .env.development up --force-recreate -d
	@echo "Development services are starting. View logs with: make logs"

# Stop and remove PastePoint containers
down:
	@echo "Stopping and removing PastePoint services..."
	@test -n "$(ENV_FILE)" || (echo "Error: no .env.development or .env.production found." && exit 1)
	docker compose --env-file $(ENV_FILE) down

# Stop PastePoint containers without removing them
stop:
	@echo "Stopping PastePoint services..."
	@test -n "$(ENV_FILE)" || (echo "Error: no .env.development or .env.production found." && exit 1)
	docker compose --env-file $(ENV_FILE) stop

# View logs
logs:
	@echo "Viewing logs (Ctrl+C to exit)..."
	@test -n "$(ENV_FILE)" || (echo "Error: no .env.development or .env.production found." && exit 1)
	docker compose --env-file $(ENV_FILE) logs -f

# Generate certificates (if needed)
certs:
	@echo "Generating self-signed certificates..."
	mkdir -p certs
	./scripts/generate-certs.sh
	@echo "Certificates generated in ./certs directory"

# Show help
help:
	@echo "PastePoint Docker Compose Management"
	@echo "-----------------------------------"
	@echo "make dev     - Start development environment"
	@echo "make prod    - Start production environment"
	@echo "make down    - Stop and remove PastePoint services"
	@echo "make stop    - Stop PastePoint services (without removing)"
	@echo "make logs    - View logs"
	@echo "make certs   - Generate self-signed certificates"
	@echo "make help    - Show this help message"

# Default target
.DEFAULT_GOAL := prod
