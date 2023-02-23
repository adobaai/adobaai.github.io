.PHONY: init
init: # Init the development environment of	this project
	pip install mkdocs-material

.PHONY: dev-server
dev-server: # Run the development server
	mkdocs serve
