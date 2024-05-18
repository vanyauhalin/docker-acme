.DEFAULT_GOAL := help

.PHONY: all
all: # Run all recipes.
all: help

.PHONY: help
help: # Show help information.
	@echo "recipes:"
	@grep --extended-regexp "^[a-z-]+: #" "$(MAKEFILE_LIST)" | \
		awk 'BEGIN {FS = ": # "}; {printf "  %-8s%s\n", $$1, $$2}'

.PHONY: build
build: # Build the Docker image.
	@docker build --tag vanyauhalin/nginx-le .
