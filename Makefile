.PHONY: dist lint clean

dist:
	@bash scripts/build-dist.sh

lint: dist
	@bash scripts/lint-schemas.sh

clean:
	@rm -rf dist/
