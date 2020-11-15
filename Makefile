# Magic Makefile Help
.PHONY: help all clean
help:
	@cat $(MAKEFILE_LIST) | grep -e "^[a-zA-Z_\-]*: *.*## *" | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

html:  ## Render html document using pandoc
	pandoc --self-contained -c github-pandoc.css -o charlie-health.html -s charlie-health.md
