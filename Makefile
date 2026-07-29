.PHONY: catalog validate

catalog:
	python3 tools/update_catalog.py

validate:
	python3 tools/validate.py
