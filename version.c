/*	$OpenBSD: version.c,v 1.12 1999/07/14 13:37:24 millert Exp $	*/

/*
 * value of $KSH_VERSION (or $SH_VERSION)
 */

#include "sh.h"

/*
 * joksh: its version, in $JOKSH_VERSION and after pdksh's in
 * $KSH_VERSION, which keeps "PD KSH" for scripts that look for it.
 * packaging/release.sh reads it from here.
 */
#define JOKSH	"joksh 1.0"

const char ksh_version [] =
	"@(#)PD KSH v5.2.14 99/07/13.2 (" JOKSH ")";
const char joksh_version [] = JOKSH;
