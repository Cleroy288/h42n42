-include Makefile.local
include Makefile.options

# Detect if dune is installed in PATH
HAS_DUNE := $(shell command -v dune 2>/dev/null)

ifeq ($(HAS_DUNE),)
# ----------------------------------------------------------------------------
# Host environment without local OCaml/dune toolchain:
# Automatically build and launch everything via Docker Compose!
# ----------------------------------------------------------------------------
all:
	@echo "==> OCaml/Dune not found on host. Starting H42N42 via Docker Compose..."
	docker compose up --build

run:
	@echo "==> Launching H42N42 container..."
	docker compose up

clean:
	@echo "==> Stopping Docker containers..."
	docker compose down 2>/dev/null || true
	rm -rf $(TEST_PREFIX) _build

fclean: clean
	@echo "==> Removing Docker containers and build cache..."
	docker compose down --rmi local -v 2>/dev/null || true
	rm -rf $(TEST_PREFIX) _build

re:
	@echo "==> Rebuilding and restarting H42N42..."
	docker compose down 2>/dev/null || true
	docker compose up --build

build:
	@echo "==> Building Docker image..."
	docker compose build

.PHONY: all run clean fclean re build

else
# ----------------------------------------------------------------------------
# Native environment (inside Docker container or host with opam/dune switch):
# Build and run using native Ocsigen/Eliom toolchain.
# ----------------------------------------------------------------------------
include Makefile.app

endif
