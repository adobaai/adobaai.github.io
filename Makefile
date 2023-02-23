.PHONY: init
init: # Init the development environment of this project
	# GitHub Action will also use this target.

	# pipx is preferred, but pip is simpler.
	pip install mkdocs-material mdx-truly-sane-lists

.PHONY: dev-server
dev-server: # Run the development server
	mkdocs serve
