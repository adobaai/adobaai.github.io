.PHONY: init
init: # Init the development environment of this project
	# GitHub Action will also use this target.

	# pipx is preferred, but pip is simpler.
	pip install mkdocs-material mdx-truly-sane-lists

# Got error when init:
#   error: externally-managed-environment
.PHONY: init-pipx
init-pipx:
	pipx install mkdocs-material --include-deps
	pipx inject mkdocs-material mdx-truly-sane-lists

.PHONY: dev-server
dev-server: # Run the development server
	mkdocs serve
