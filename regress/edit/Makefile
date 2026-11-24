# Line editing tests, from OpenBSD's regress/bin/ksh/edit.
#
# Build the shell first; "make test" at the top of the tree builds it and
# then runs these. The scripts are run by the shell under test, not by
# the system's sh, whose echo(1) differs too much between systems.

CC ?=		cc
KSH ?=		../../oksh
LIBUTIL ?=	-lutil

# The last run checks that multiline changes nothing on a terminal
# without what it needs.
all: edit
	${KSH} ./emacs.sh . ${KSH}
	${KSH} ./vi.sh . ${KSH}
	TERM=dumb KSHFLAGS="-o multiline" ${KSH} ./vi.sh . ${KSH}

# The harness takes strtonum() from oksh's compatibility code when the
# system has none.
edit: edit.c
	${CC} ${CFLAGS} -I../.. -o edit edit.c ../../strtonum.c ${LIBUTIL}

clean:
	rm -f edit

.PHONY: all clean
