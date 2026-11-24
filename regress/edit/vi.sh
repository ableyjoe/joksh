#!/bin/sh
#
# $OpenBSD: vi.sh,v 1.14 2026/04/04 09:33:18 jtt Exp $
#
# Copyright (c) 2016 Ingo Schwarze <schwarze@openbsd.org>
# Copyright (c) 2017 Anton Lindqvist <anton@openbsd.org>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

. "${1:-.}/subr.sh"

KSH=$2

EDITOR=
ENV=
HISTFILE=
MAIL=
PS1=' # '
VISUAL=vi
export EDITOR ENV HISTFILE MAIL PS1 VISUAL

# The function testseq() sets up a pseudo terminal and feeds its first
# argument to a shell on standard input.  It then checks that output
# from the shell to the pseudo terminal agrees with the second argument.

# ^H, ^?: Erase.
testseq "ab\bc" " # ab\b \bc"
testseq "ab\0177c" " # ab\b \bc"

# ^J, ^M: End of line.
testseq "echo a\nb" " # echo a\r\r\na\r\n # b"
testseq "echo a\rb" " # echo a\r\r\na\r\n # b"
testseq "echo a\0033\nb" " # echo a\b\r\r\na\r\n # b"
testseq "echo a\0033\rb" " # echo a\b\r\r\na\r\n # b"

# ^U: Kill.
testseq "ab\0033ic\0025d" " # ab\bcb\b\b\bb  \b\b\bdb\b"

# ^V: Literal next.
testseq "a\0026\0033b" " # a^\b^[b"

# ^W: Word erase.
testseq "one two\0027rep" " # one two\b\b\b   \b\b\brep"

# A: Append at end of line.
# 0: Move to column 0.
testseq "one\00330A two" " # one\b\b\bone two"
testseq "one\003302A two\0033" " # one\b\b\bone two two\b"
testseq "\0200abcdef\00330lrxll" " # \0200abcdef\b\r # \0200x\bxb"
testseq "\0270\0202A\00330i\0340\0033" " # \0270\0202A\b\b\0340\0270\0202A\b\b"
testseq "\0200abcdef\00330ix\0033" \
	" # \0200abcdef\b\r # x\0200abcdef\r # x\0200\b"

# a: Append.
# .: Redo.
testseq "ab\00330axy" " # ab\b\baxb\byb\b"
testseq "ab\003302axy\0033" " # ab\b\baxb\byb\bxyb\b\b"
testseq "ab\00330axy\0033." " # ab\b\baxb\byb\b\byxyb\b\b"

# UTF-8 continuation bytes: The cursor stays inside the line after Esc,
# $ and a.
testseq "\0251\0033" " # \0251\b"
testseq "\0251\0251\0033\$" " # \0251\0251\b"
testseq "#\0303\0251\n#\0303\0033ab" " # #\0303\0251\r\r\n # #\0303\b\0303b"
testseq "\0303\0251x\00330ay" " # \0303\0251x\b\b\0303\0251yx\b"

# B: Move back big word.
testseq "one 2.0\0033BD" " # one 2.0\b\b\b   \b\b\b\b"

# b: Move back word.
# C: Change to end of line.
# D: Delete to end of line.
testseq "one ab.cd\0033bDa.\00332bD" \
	" # one ab.cd\b\b  \b\b\b..\b\b\b\b    \b\b\b\b\b"
testseq "one two\0033bCrep" " # one two\b\b\b   \b\b\brep"
testseq "\0302\0251\0303\0200a\0033DP" \
	" # \0302\0251\0303\0200a\b \b\ba\0303\0200\b\b"

# c: Change region.
testseq "one two\0033cbrep" " # one two\b\b\bo  \b\b\bro\beo\bpo\b"
testseq "one two\00332chx" " # one two\b\b\bo  \b\b\bxo\b"

# d: Delete region.
testseq "one two\0033db" " # one two\b\b\bo  \b\b\b"
testseq "one two xy\00332db" " # one two xy\b\b\b\b\b\by     \b\b\b\b\b\b"

# E: Move to end of big word.
testseq "1.00 two\00330ED" " # 1.00 two\b\r # 1.0     \b\b\b\b\b\b"

# e: Move to end of word.
testseq "onex two\00330eD" " # onex two\b\r # one     \b\b\b\b\b\b"

# F: Find character backward.
# ;: Repeat last search.
# ,: Repeat last search in opposite direction.
testseq "hello\00332FlD" " # hello\b\b\b   \b\b\b\b"
testseq "hello\0033Flix\0033;ix" " # hello\b\bxlo\b\b\b\bxlxlo\b\b\b\b"
testseq "hello\00332Flix\00332,ix" " # hello\b\b\bxllo\b\b\b\bxlxlo\b\b"

# f: Find character forward.
testseq "hello\003302flD" " # hello\b\b\b\b\bhel  \b\b\b"
# A multi-byte character is matched whole, not by its first byte.
testseq "a\0303\0251\0303\0274bc\00330f\0303\0274D" \
	" # a\0303\0251\0303\0274bc\0010\0010\0010\0010\0010a\0303\0251    \0010\0010\0010\0010\0010"
# So it is after c, d and y, of four bytes, and before t and T stop.
testseq "a\0303\0251bc\0303\0251d\00330df\0303\0251" \
	" # a\0303\0251bc\0303\0251d\b\r # bc\0303\0251d   \r # "
testseq "a\0303\0251bc\00330dtb" " # a\0303\0251bc\b\b\b\bbc   \r # "
testseq "a\0360\0237\0230\0200b\00330df\0360\0237\0230\0200" \
	" # a\0360\0237\0230\0200b\b\b\bb     \r # "
testseq "a\0303\0251bc\0033T\0303\0251x" " # a\0303\0251bc\b\bc \b\b"

# h, ^H: Move left.
# i: Insert.
testseq "hello\00332hix" " # hello\b\b\bxllo\b\b\b"
testseq "hello\00332\b2ix\0033" " # hello\b\b\bxllo\b\b\bxllo\b\b\b\b"

# I: Insert before first non-blank.
# ^: Move to the first non-whitespace character.
testseq "  ab\0033Ixy" " #   ab\b\bxab\b\byab\b\b"
testseq "  ab\00332Ixy\0033" " #   ab\b\bxab\b\byab\b\bxyab\b\b\b"
testseq "  ab\0033^ixy" " #   ab\b\bxab\b\byab\b\b"

# L: Undefined command (beep).
testseq "ab\0033Lx" " # ab\b\a \b\b"

# l, space: Move right.
# ~: Change case.
testseq "abc\003302l~" " # abc\b\b\babC\b"
testseq "abc\00330 rx" " # abc\b\b\bax\b"

# P: Paste at current position after delete.
testseq "abcde\0033hDhP" " # abcde\b\b  \b\b\b\bdebc\b\b\b"
testseq "abcde\0033hDh2P" " # abcde\b\b  \b\b\b\bdedebc\b\b\b"
testseq "A\0033xa\0303\0200\00332Px" \
	" # A\b \b\0303\0200\bAA\0303\0200\b\b\0303\0200 \b\b"
testseq "\0302\0251\0033xaA\0033Px" \
	" # \0302\0251\b  \b\bA\b\0302\0251A\b\bA  \b\b\b"
testseq "\0302\0251\0033xa\0303\0200\0033Px" \
 " # \0302\0251\b  \b\b\0303\0200\b\0302\0251\0303\0200\b\b\0303\0200  \b\b\b"

# P: Paste at current position after change.
testseq "abcde\0033hC\0033hP" " # abcde\b\b  \b\b\b\bdebc\b\b\b"
testseq "abcde\0033hC\0033h2P" " # abcde\b\b  \b\b\b\bdedebc\b\b\b"
testseq "A\0033cl\0033a\0303\0200\00332Pcl\0033" \
	" # A\b \b\0303\0200\bAA\0303\0200\b\b\0303\0200 \b\b\b"
testseq "\0302\0251\0033cl\0033aA\0033Pcl\0033" \
	" # \0302\0251\b  \b\bA\b\0302\0251A\b\bA  \b\b\b"
testseq "\0302\0251\0033cl\0033a\0303\0200\0033Pcl\0033" \
 " # \0302\0251\b  \b\b\0303\0200\b\0302\0251\0303\0200\b\b\0303\0200  \b\b\b"
testseq "one two \0033ccthree\00330P" \
	" # one two \b\r #        \r # three\b\b\b\b\bone two three\b\b\b\b\b\b"
testseq "one zero\0033bcw\00330Pa \0033" \
	" # one zero\b\b\b\b    \b\b\b\b\b\b\b\bzeroone\b\b\b\bo one\b\b\b\b"
testseq "one zero \0033bcf \00330P" \
	" # one zero \b\b\b\b\b    \b\b\b\b\b\b\b\bzero one\b\b\b\b"

# p: Paste after current position after delete.
testseq "abcd\0033hDhp" " # abcd\b\b  \b\b\b\bacdb\b\b"
testseq "abcd\0033hDh2p" " # abcd\b\b  \b\b\b\bacdcdb\b\b"
testseq "A\0033xa\0303\0200\0033px" " # A\b \b\0303\0200\b\0303\0200A\b \b\b"
testseq "\0302\0251\0033xaA\0033px" \
	" # \0302\0251\b  \b\bA\bA\0302\0251\b  \b\b\b"
testseq "\0302\0251\0033xa\0303\0200\0033px" \
	" # \0302\0251\b  \b\b\0303\0200\b\0303\0200\0302\0251\b  \b\b\b"

# p: Paste after current position after change.
testseq "abcd\0033hC\0033hp" " # abcd\b\b  \b\b\b\bacdb\b\b"
testseq "abcd\0033hC\0033h2p" " # abcd\b\b  \b\b\b\bacdcdb\b\b"
testseq "A\0033cl\0033a\0303\0200\0033pcl\0033" \
	" # A\b \b\0303\0200\b\0303\0200A\b \b\b"
testseq "\0302\0251\0033cl\0033aA\0033pcl\0033" \
	" # \0302\0251\b  \b\bA\bA\0302\0251\b  \b\b\b"
testseq "\0302\0251\0033cl\0033a\0303\0200\0033pcl\0033" \
	" # \0302\0251\b  \b\b\0303\0200\b\0303\0200\0302\0251\b  \b\b\b"
testseq "one two\0033cczero \0033p" \
	" # one two\b\r #        \r # zero \b one two\b"
testseq "one zero\00330cw\0033\$a \0033p" \
	" # one zero\b\r #  zero   \r #  zero \b one\b"
testseq "one zero\00330cf \0033\$a \0033p" \
	" # one zero\b\r # zero    \r # zero \b one"

# R: Replace.
testseq "abcd\00332h2Rx\0033" " # abcd\b\b\bxx\b"
testseq "abcdef\00334h2Rxy\0033" " # abcdef\b\b\b\b\bxyxy\b"

# r: Replace character.
testseq "abcd\00332h2rxiy" " # abcd\b\b\bxx\byxd\b\b"
testseq "\0303\0266\0033ro" " # \0303\0266\bo \b\b"
testseq "\0342\0202\0254\0033ro" " # \0342\0202\0254\bo  \b\b\b"
testseq "\0303\0266\00332ro" " # \0303\0266\b\a"
# Replace with a multi-byte character, not just its first byte.
testseq "x\0033r\0303\0266" " # x\0010\0303\0266\0010"
# A character cut short is an error.
testseq "x\0033r\0360x" " # x\b\a"

# S: Substitute whole line.
testseq "oldst\0033Snew" " # oldst\b\b\b\b\b     \r # new"
testseq "oldstr\033Snew" " # oldstr\b\r #       \r # new"

# s: Substitute.
testseq "abcd\00332h2sx" " # abcd\b\b\bd  \b\b\bxd\b"
testseq "\0303\0266\0033s" " # \0303\0266\b  \b\b"

# T: Move backward after character.
testseq "helloo\0033TlD" " # helloo\b\b  \b\b\b"
testseq "hello\00332TlD" " # hello\b\b  \b\b\b"

# t: Move forward before character.
testseq "abc\00330tcD" " # abc\b\b\ba  \b\b\b"
testseq "hello\003302tlD" " # hello\b\b\b\b\bhe   \b\b\b\b"

# U: Undo all changes.
testseq "test\0033U" " # test\b\b\b\b    \b\b\b\b"

# u: Undo.
testseq "test\0033hxu" " # test\b\bt \b\bst\b\b"

# W: Move forward big word.
testseq "1.0 two\00330WD" " # 1.0 two\b\r # 1.0    \b\b\b\b"

# w: Move forward word.
testseq "ab cd ef\003302wD" " # ab cd ef\b\r # ab cd   \b\b\b"

# X: Delete previous character.
testseq "abcd\00332X" " # abcd\b\b\bd  \b\b\b"

# x: Delete character.
# |: Move to column.
testseq "abcd\00332|2x" " # abcd\b\b\bd  \b\b\b"
testseq "\0303\0266a\0033xx" " # \0303\0266a\b \b\b  \b\b"

# Y: Yank to end of line.
testseq "abcd\0033hYp" " # abcd\b\bccdd\b\b"

# y: Yank region.
# $: Move to the last character.
testseq "abcd\00332h2ylp" " # abcd\b\b\bbbccd\b\b\b"
testseq "abcd\00332h2yl\$p" " # abcd\b\b\bbcdbc\b"

# %: Find match.
testseq "(x)\0033%lrc" " # (x)\b\b\b(c\b"
testseq "(x)\00330%hrc" " # (x)\b\b\b(x\bc\b"

# ^R: Redraw.
testseq "test\0033h\0022" " # test\b\b\r\r\n # test\b\b"

# ASCII resize: cols=1/11/12
testseq "aaaaaaaaaabbbbbbbbbb\0033hhhhhhhhhhhhhhhhhhh\000RS1" \
	" # aaaaaaaaaabbbbbbbbbb\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\r\033[J# aaaaaaa >\r# "
testseq "aaaaaaaaaabbbbbbbbbb\0033hhhhhhhhh\000RS11" \
	" # aaaaaaaaaabbbbbbbbbb\b\b\b\b\b\b\b\b\b\b\r\033[J# aaabbbb +\b\b\b\b\b\b"
testseq "aaaaaaaaaabbbbbbbbbb\0033\000RS12" \
	" # aaaaaaaaaabbbbbbbbbb\b\r\033[J# bbbb    <\b\b\b\b\b\b"

# ASCII resize: cols=13, cursor -1/0/+1
testseq "aaaaaaaaaabbbbbbbbbb\0033hhhhhhhhhhhhh\000RS13" \
	" # aaaaaaaaaabbbbbbbbbb\b\b\b\b\b\b\b\b\b\b\b\b\b\b\r\033[J # aaaaaaa >\b\b\b"
testseq "aaaaaaaaaabbbbbbbbbb\0033hhhhhhhhhhhh\000RS13" \
	" # aaaaaaaaaabbbbbbbbbb\b\b\b\b\b\b\b\b\b\b\b\b\b\r\033[J # aaaaaab +\b\b\b\b\b\b"
testseq "aaaaaaaaaabbbbbbbbbb\0033hhhhhhhhhhh\000RS13" \
	" # aaaaaaaaaabbbbbbbbbb\b\b\b\b\b\b\b\b\b\b\b\b\r\033[J # aaaaabb +\b\b\b\b\b\b"

# ASCII resize: cols=79/80/81
testseq "aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccc\0033hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh\000RS79" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccc\r # bbbbbbbbbbbbbcccccccccccccccccccccccc                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\bc\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\baaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbcccccccccccccccccccccccc >\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\r\033[J # aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccc >\r # "
testseq "aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccc\0033hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh\000RS80" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccc\r # bbbbbbbbbbbbbcccccccccccccccccccccccc                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\bc\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\baaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbcccccccccccccccccccccccc >\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"
testseq "aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccc\0033hhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh\000RS81" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccc\r # bbbbbbbbbbbbbcccccccccccccccccccccccc                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\bc\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\baaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbcccccccccccccccccccccccc >\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\r\033[J # aaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbccccccccccccccccccccccccc >\r # "

# ASCII window indicator at left edge
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbb" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbb\r # aaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbb                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"

# UTF-8 window indicator at left edge
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0303\0266bbbbbbbbb" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0303\0266bbbbbbbb\r # aaaaaaaaaaaaaaaaaaaaaaaaaaa\0303\0266bbbbbbbbb                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"

# ASCII window indicator at right edge
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabb\00330" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\bbb\b\baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >\r # "

# UTF-8 window indicator at right edge
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0303\0266b\00330" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\0303\0266b\b\baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >\r # "

# ASCII window indicator on both sides
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\003340h" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\baaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\r # aaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb                                    \b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\r # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbbbbbbbbbbbb +\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"

# UTF-8 window indicator on both sides
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0303\0266bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\003340h" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\baaaaaa\0303\0266bbbbbbbbbbbbbbbbbbbbbbbbbbbbb\r # aaaaaa\0303\0266bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb                                    \b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\r # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0303\0266bbbbbbbbbbbbbbbbbbbbbbbbbb +\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b"

# ASCII redraw at right edge
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaabb\00330\0022" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\bbb\b\baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >\r # \r\r\n # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >\r # "

# UTF-8 redraw at right edge
testseq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\0303\0266b\00330\0022" \
	" # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b                                      <\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\b\0303\0266b\b\baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >\r # \r\r\n # aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >\r # "

# The prompt width: A carriage return starts again from zero, and a tab
# goes to the next tab stop.
a66=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
PS1=$(echo 'xy\r # ')
testseq "${a66}aaaaaaa" "xy\r # ${a66}aaaaaaa"
PS1=$(echo 'x\t# ')
testseq "$a66" "x\t# $a66"

# A UTF-8 prompt takes a column for each character, not each byte:
# 72 characters fit after this 3-column prompt in 80 columns.
PS1=$(printf '\303\251\342\206\222 ')
x=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
testseq "$x" "\0303\0251\0342\0206\0222 $x"
PS1=' # '

# A run of stray UTF-8 continuation bytes, which take no column, still
# fits in the window buffers.
c10='\0200\0200\0200\0200\0200\0200\0200\0200\0200\0200'
c100=$c10$c10$c10$c10$c10$c10$c10$c10$c10$c10
testseq "a$c100$c100$c100$c100" " # a\ba$c100$c100$c100$c100"

# Completing a word with a control character in it, which is not taken
# for word-code.
testseq "T\0026\0007\0033=" " # T^\b^G\b\a"

# A search that was interrupted leaves nothing behind for the next one,
# and a count before / starts a search as it does without one.
testseq "\0033/abc\0003\0033/\0027a" " # /abc^C\r\n # /a"
testseq "\0033/abc\0003\0033/\0010a" " # /abc^C\r\n # /\b \b"
testseq "abc\00332/x\0003" " # abc\b\b\b/  \b\bx^C\r\n # "

# set -o multiline: Long lines continue on the following screen lines.
# The terminal is 80 columns wide. The xterm terminfo entry has
# automatic margins, cursor up (\E[A) and clear to end of screen (\E[J).
TERM=xterm
export TERM
KSHFLAGS="-o multiline"
ED='\0033[J'
UP='\0033[A'

a76=$(rep 76 a)
t77="a$ED$a76"		# 77 a typed: clear the screen once, at the start

# Control characters are shown as in a single line.
testseq "\0026\0001" " # ^$ED\b^A"

# After the last column: A blank and a carriage return, so that the
# cursor is at the start of the next line on all terminals.
testseq "${a76}ab" " # $t77 \rb"

# The screen width is not hardcoded: the same wrapping on 20 columns.
EDITFLAGS="-w 20"
testseq "$(rep 17 a)ab" " # a$ED$(rep 16 a) \rab"
EDITFLAGS=

# When the terminal changes width, the line is drawn again from where
# the prompt begins, or from lower down if the line takes fewer rows at
# the new width: terminals that wrap it again put it there.
testseq "${a76}ab\000RS60" " # $t77 \rb\r$UP\r$ED # ${a76}ab$ED"
testseq "$(rep 100 a)\000RS120" \
    " # $t77 \r$(rep 23 a)\r\r$ED # $(rep 100 a)$ED"

# Moving to an earlier line: Set the column, then move up.
testseq "${a76}ab\00330" " # $t77 \rb\bb  $UP"

# Changes are drawn from the first changed character.
testseq "${a76}ab\00330iX" " # $t77 \rb\bb  ${UP}X${a76}ab  $UP"

# A shorter line clears what is left of the old one.
testseq "${a76}ab\00330x" " # $t77 \rb\bb  $UP\0033[76Cb \r$ED   $UP"

# Moving to a later line, before an interrupt.
testseq "${a76}ab\00330\0003" " # $t77 \rb\bb  $UP\r\n\rb^C\r\n # "

# A line that fills its last line is not followed by an empty line.
testseq "#${a76}\n" " # #$ED$a76 \r$UP\r\r\n # "

# A UTF-8 character and a tab starting at the end of a line. The
# character is drawn once it is whole, as terminals differ on what to
# show for part of one.
testseq "${a76}a\0303\0251b" " # $t77 \r\0303\0251b"
testseq "$(rep 75 a)\0026\tb" " # a$ED$(rep 74 a)^\b     b"

# A character that may not take one column, such as a combining mark or
# a wide one, has the line shown in the window, on a new line.
testseq "ab e\0314\0201c" " # a${ED}b e\r\r\n # ab e\0314\0201c"
testseq "ab\0344\0270\0255c" " # a${ED}b\r\r\n # ab\0344\0270\0255c"
testseq "a\0342\0206\0222b" " # a$ED\0342\0206\0222b"

# ^R: Redraw on a new line.
testseq "${a76}ab\0022" " # $t77 \rb\r\r\n # ${a76}ab$ED"

# History: Lines of different lengths in turn.
testseq "#${a76}ab\n#x\n\0033kkj" \
    " # #$ED$a76 \rab\r\r\n # #${ED}x\r\r\n # #x$ED\b\b#${a76}ab $UP#x$ED\b\b"

# The width of the last line of the prompt, after a carriage return.
PS1="xy$(echo '\r') # "
testseq "${a76}ab" "xy\r # $t77 \rb"

# A prompt wider than the screen is not truncated.
PS1="$(rep 85 p) # "
testseq "ab\00330" "${PS1}a${ED}b\b\b"

# A prompt that fills its line: ^D, and no empty line after a newline.
PS1="$(rep 77 p) # "
testseq "\n" "$PS1 \r$UP\r\r\n$PS1 \r"
testseq "\0004" "$PS1 \r^D\r\r"
PS1=' # '

# A line taller than the screen continues in the window.
EDITFLAGS="-l 2"
testseq "#$(rep 157 a)b" \
    " # #$ED$a76 \r${a76}aaa\r\r\n # $(rep 37 a)$(rep 38 ' ')<$(rep 39 '\b')ab"
EDITFLAGS=

# Moving right: The terminal's sequence if it is shorter, else the cells.
testseq "${a76}ab\0033h" " # $t77 \rb\b\0033[79C$UP"
# Moving left a long way: Start again from the first column.
testseq "${a76}a$(rep 40 b)\00330" " # $t77 \r$(rep 40 b)\b\r\0033[3C$UP"
testseq "$(rep 70 a)\00330" " # a$ED$(rep 69 a)\b\r\0033[3C"
TERMINFO=$(mktemp -d)
export TERMINFO
printf 'xtest|no cursor right,\n\tam, cols#80, lines#24,\n' >$TERMINFO/xtest.src
printf '\tbel=^G, cr=\\r, cuu1=\\E[A, ed=\\E[J,\n' >>$TERMINFO/xtest.src
tic $TERMINFO/xtest.src
TERM=xtest
testseq "${a76}ab\0033h" " # $t77 \rb\bb$(rep 78 ' ')$UP"
rm -r $TERMINFO
unset TERMINFO
TERM=xterm

# Motions across lines: w, b, $, counts, and back to the first column.
testseq "$(rep 70 a) bb cc dd ee\00330wwwb" \
    " # a$ED$(rep 69 a) bb cc  \rdd ee\b\b$UP\0033[71Cbb \r\n\r\0033[77C$UP"
testseq "${a76}ab\00330\$" " # $t77 \rb\bb  $UP\r\n\r"
testseq "${a76}ab\0033030l25h" " # $t77 \rb\bb  $UP\0033[30C\r\0033[8C"
testseq "${a76}abcdef\00334h" " # $t77 \rbcdef\b\r"

# ^L and ^U. (A search cannot be tested here: edit waits for a prompt
# after the newline that ends it.)
testseq "${a76}ab\0014" " # $t77 \rb\0033[H\0033[2J # ${a76}ab$ED"
testseq "${a76}ab\0025" " # $t77 \rb  $UP$ED"

# Deleting at the end. Bytes that are not valid UTF-8, here a character
# cut short and a stray continuation byte, have the line shown in the
# window, on a new line.
testseq "${a76}ab\0033x" " # $t77 \rb\b \r$ED\0033[79C$UP"
HISTFILE=$(mktemp)
echo "#\0303X" >$HISTFILE
testseq "#\0303\0251\0033k" " # #$ED\0303\0251\b\r\r\n # #\0303X\b\b\b"
rm -f $HISTFILE
HISTFILE=
testseq "\0251\0033" " # \r\r\n # \0251\b"

# Characters of more than one cell split between lines.
testseq "$(rep 75 a)\0026\tb\00330\$" \
    " # a$ED$(rep 74 a)^\b     b\b$UP\r\n\r   "
testseq "${a76}\0026\0001b\00330\$" \
    " # a$ED$(rep 75 a)^ \r\0033[79C$UP^Ab\bb $UP\r\n\rA"
testseq "\0026\0177" " # ^$ED\b^?"
testseq "abcde\0026\tf\003304ll" " # a${ED}bcde^\b   f\b\r\0033[3Cabcde  "
testseq "abc\0026\0001d\003303l" " # a${ED}bc^\b^Ad$(rep 6 '\b')abc^"
KSHFLAGS="-o multiline -o vi-show8"
testseq "${a76}\0201b" " # a$ED$(rep 75 a)M-^Ab"
KSHFLAGS="-o multiline"

# Completion lists are printed below the line.
mldir=$(mktemp -d /tmp/ml.XXXXXXXX)
touch $mldir/f1 $mldir/f2
cl="#$(rep 70 a) $mldir/f"	# the line
cs="${mldir#/tmp/}/f"		# its last part
cf='\r\r\nf1  f2  \r\n'		# the list
testseq "$cl\0005" " # #$ED$(rep 70 a) /tmp/ \r$cs$cf # $cl$ED"
testseq "$cl\00335\0134" " # #$ED$(rep 70 a) /tmp/ \r$cs\b\0007$cf # $cl$ED\b"
KSHFLAGS=
w1=" # #$(rep 70 a) /\r # $(rep 34 a) /t$(rep 38 ' ')<$(rep 39 '\b')mp/$cs"
w2=" # $(rep 34 a) $mldir/f$(rep 22 ' ')<"
testseq "$cl\0005" "$w1$cf$w2$(rep 23 '\b')"
testseq "$cl\00335\0134" "$w1\b\0007$cf$w2$(rep 24 '\b')"
KSHFLAGS="-o multiline"
rm -r $mldir

# More prompts: \n and \r, a newline, a tab, and one of no width.
PS1='xy\n # '
PROMPT=$(echo 'xy\r\n # ')
testseq "${a76}ab" "xy\r\n # $t77 \rb"
PS1='xy\r # '
PROMPT=$(echo 'xy\r # ')
testseq "${a76}ab" "xy\r # $t77 \rb"
PS1=$(echo 'xy\n # ')
PROMPT=$(echo 'xy\r\n # ')
testseq "${a76}ab" "xy\r\n # $t77 \rb"
PS1=$(echo 'x\t# ')
PROMPT=$PS1
testseq "$(rep 70 a)ab" "x\t# a$ED$(rep 69 a) \rab"
PS1="$(echo '\0001\r\0001\0033[0m\0001')"
PROMPT="$(echo '\0001\0033[0m\0001')"
testseq "\n" "$PROMPT\r\r\n$PROMPT"
PS1=$(echo '\\[\0033[0m\\] # ')
PROMPT=$(echo '\0033[0m # ')
testseq "${a76}ab" "\0033[0m # $t77 \rb"
PS1=$(echo '\0001\r\0001\\a\0001 # ')
PROMPT=$(echo '\0001\0007\0001 # ')
testseq "${a76}ab" "\0001\0007\0001 # $t77 \rb"
PS1=' # '
PROMPT=

# The height of the screen is not known.
EDITFLAGS="-l 0"
testseq "#$(rep 157 a)b" " # #$ED$a76 \r$(rep 80 a) \rab"
EDITFLAGS=

# Without the option, and after turning it off.
KSHFLAGS=
testseq "${a76}ab" \
    " # $(rep 73 a)$(rep 36 '\b')$(rep 38 ' ')<$(rep 39 '\b')aaab"
testseq "abc\0003" " # abc^C\r\n # "
testseq "\0004" " # ^D\r\r"
w3=" # $(rep 73 a)^ >$(rep 41 '\b')^A$(rep 38 ' ')<"
testseq "$(rep 73 a)\0026\0001\00330" "$w3$(rep 41 '\b')$(rep 38 a)^ >\r # "
testseq "$(rep 73 a)\0026\0001" "$w3$(rep 39 '\b')"
KSHFLAGS="-o vi-show8"
testseq "$(rep 72 a)\0201" \
    " # $(rep 72 a)\r # $(rep 33 a)M-^A$(rep 38 ' ')<$(rep 39 '\b')"
KSHFLAGS="-o multiline"
testseq "set +o multiline\nab" " # s${ED}et +o multiline\r\r\n # ab"

# Terminals without what the option needs: unknown, no automatic margins,
# no clear to end of screen, and empty cursor up or clear to end of screen.
TERM=no-such-terminal
testseq "#ab\ncd" " # #ab\r\r\n # cd"
TERMINFO=$(mktemp -d)
export TERMINFO
c='cols#80, lines#24, bel=^G, cr=\r'
for e in "xnoam|no am, $c, cuu1=\E[A, ed=\E[J," \
    "xnoed|no ed, am, $c, cuu1=\E[A," \
    "xnocuu|empty cuu1, am, $c, cuu1=, ed=\E[J," \
    "xnoed2|empty ed, am, $c, cuu1=\E[A, ed=,"
do
	printf '%s\n' "$e" >$TERMINFO/e.src
	tic $TERMINFO/e.src
done
for TERM in xnoam xnoed xnocuu xnoed2; do
	testseq "ab" " # ab"
done
rm -r $TERMINFO
unset TERMINFO
TERM=xterm

# Without the terminal capabilities, long lines are scrolled.
TERM=dumb
testseq "ab" " # ab"
