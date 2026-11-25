COMMENT=	portable OpenBSD ksh with multi-line editing

V=		1.0
DISTNAME=	joksh-${V}
CATEGORIES=	shells
HOMEPAGE=	https://github.com/ableyjoe/joksh

# Public domain, with BSD and ISC licensed portability files
PERMIT_PACKAGE=	Yes

SITES=		https://github.com/ableyjoe/joksh/releases/download/joksh-${V}/

WANTLIB=	c curses

CONFIGURE_STYLE=simple
CONFIGURE_ARGS=	--prefix=${PREFIX} \
		--mandir=${PREFIX}/man

.include <bsd.port.mk>
