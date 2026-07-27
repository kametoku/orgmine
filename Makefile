EMACS ?= emacs -batch -q -Q --no-site-file

all: orgmine.elc
orgmine.elc: orgmine.el
	$(EMACS) $(LOAD) -l test/test-helper.el \
	-batch -f batch-byte-compile $<

test: orgmine.elc
	$(EMACS) $(EMACSFLAGS) -l ert \
		-l test/test-helper.el \
		-l orgmine.el \
		-l test/orgmine-tests.el \
		-f ert-run-tests-batch-and-exit

clean:
	rm -f orgmine.elc

distclean: clean
	rm -fr .test-elpa
