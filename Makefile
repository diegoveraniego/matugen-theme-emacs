EMACS ?= emacs
PYTHON ?= python3

.PHONY: test compile validate

test:
	$(EMACS) --batch -Q -L . -l test/matugen-theme-test.el -f ert-run-tests-batch-and-exit

compile:
	$(EMACS) --batch -Q -L . --eval '(progn (require (quote bytecomp)) (let ((byte-compile-error-on-warn t)) (unless (and (byte-compile-file "matugen-theme-faces.el") (byte-compile-file "matugen-theme.el")) (kill-emacs 1))))'

validate:
	$(EMACS) --batch -Q -L . -l tools/export-palettes.el
	$(PYTHON) tools/check-palettes.py
