#------------------------------------------------------------
# Makefile for MIME::
#------------------------------------------------------------

# Where to install the libraries:
SITE_PERL = /usr/lib/perl/site_perl

# What Perl5 is called on your system (no need to give entire path):
PERL5     = perl

# You probably won't need to change these...
MODS      = Decoder.pm Entity.pm Head.pm Parser.pm
SHELL     = /bin/sh

#------------------------------------------------------------
# For installers...
#------------------------------------------------------------

help:	
	@echo "Valid targets: test clean install"

clean:
	rm -f testout/*

test:
	@echo "TESTING Head.pm..."
	${PERL5} MIME/Head.pm   < testin/first.hdr       > testout/Head.out
	@echo "TESTING Decoder.pm..."
	${PERL5} MIME/Decoder.pm < testin/quot-print.body > testout/Decoder.out
	@echo "TESTING Parser.pm (simple)..."
	${PERL5} MIME/Parser.pm < testin/simple.msg      > testout/Parser.s.out
	@echo "TESTING Parser.pm (multipart)..."
	${PERL5} MIME/Parser.pm < testin/multi-2gifs.msg > testout/Parser.m.out
	@echo "All tests passed... see ./testout/MODULE*.out for output"

install:
	@if [ ! -d ${SITE_PERL} ]; then \
	    echo "Please edit the SITE_PERL in your Makefile"; exit -1; \
        fi          
	@if [ ! -w ${SITE_PERL} ]; then \
	    echo "No permission... should you be root?"; exit -1; \
        fi          
	@if [ ! -d ${SITE_PERL}/MIME ]; then \
	    mkdir ${SITE_PERL}/MIME; \
        fi
	install -m 0644 MIME/*.pm ${SITE_PERL}/MIME


#------------------------------------------------------------
# For developer only...
#------------------------------------------------------------

POD2HTML       = pod2html2
POD2HTML_FLAGS = --podpath=. --flush --htmlroot=..
HTMLS          = ${MODS:.pm=.html}
VPATH          = MIME

.SUFFIXES: .pm .pod .html

dist: documented	
	VERSION=1.10 ; \
	mkdist -tgz MIME-parser-$$VERSION

documented: ${HTMLS} ${MODS}

.pm.html:
	${POD2HTML} ${POD2HTML_FLAGS} \
		--title=MIME::$* \
		--infile=$< \
		--outfile=docs/$*.html

#------------------------------------------------------------
