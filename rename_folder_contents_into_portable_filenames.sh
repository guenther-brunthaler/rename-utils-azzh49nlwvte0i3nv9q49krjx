#! /bin/sh
#
# Copy this script into the top-level directory of the directory tree where
# all files and folders shall be renamed into portable names. Then
# double-click this script from within your file manager in order to run it.
#
# Version 2016.155.2
# Copyright (c) 2016 Guenther Brunthaler. All rights reserved.
#
# This source file is free software.
# Distribution is permitted under the terms of the GPLv3.

set -e

# If a file extension is longer than this value, it will be interpreted as
# part of the filename and no file extension being present.
#
# This is a countermeasure to avoid interpreting parts of filenames as file
# extensions which look like URLs and contain a single dot somewhere in the
# domain name, or contain a filename with a file extension as an embedded part
# of the URL.
#
# Set to an empty string in order to disable file extension length checks.
max_ext_len=8

# Simulation mode.
debug=false

println() {
	printf '%s\n' "$*"
}

inform() {
	xmessage "$1" 2> /dev/null || println "$1" >& 2 || :
}

cleanup() {
	local rc=$?
	$redir5 && exec 5>& -
	test -n "$helper" && wait $helper || :
	test -n "$fifo" && rm -- "$fifo"
	test $rc = 0 || inform "script $0 failed!"
}

fifo=
helper=
redir5=false

trap cleanup 0

# Replacements containing UNICODE characters, encoded in UTF-7.
locale_replacements='
	s/+AMQ-/Ae/g
	s/+ANY-/Oe/g
	s/+ANw-/Ue/g
	s/+AOQ-/ae/g
	s/+APY-/oe/g
	s/+APw-/ue/g
	s/+AN8-/ss/g
	s/+IKw-/ euro /g
	s/+ALA-/ degrees /g
'
locale_replacements=`println "$locale_replacements" | iconv -f UTF-7`

# Replacements which require only ASCII characters.
all_replacements=$locale_replacements'
	s/"/ inch /g
	s/\$/ dollar /g
	s/@/ at /g
	s/%/ percent /g
	s/'\''/ quote /g
	s/&/ and /g
	s/#/ hash /g
	s/=/ equals /g
	s/[^-a-z0-9]\+/_/g
	s/^_//; s/_$//
'

rename() {
	println "$1" | tr A-Z a-z | LC_CTYPE=POSIX sed "$all_replacements"
}

# $new:= mknew($1, $dir, $ext)
mknew() {
	new=$1
	test -n "$ext" && new=$new.$ext
	new=$dir/$new; new=${new#./}
}

process() {
	local dir bn ext old new cnt t
	dir=`dirname -- "$1"`
	bn=`basename -- "$1"`
	old=$dir/$bn; old=${old#./}
	ext=${bn##*.}
	if test x"$ext" = x"$bn" || test x"${bn#.}" != x"$bn"
	then
		ext=
	else
		if test -n "$max_ext_len" && test ${#ext} -gt $max_ext_len
		then
			ext=
		else
			ext=`rename "$ext"`
			bn=${bn%."$ext"}
		fi
	fi
	bn=`rename "$bn"`
	mknew "$bn"
	if test x"$new" != x"$old"
	then
		cnt=2
		while test -e "$new"
		do
			mknew "${bn}_$cnt"
			cnt=`expr $cnt + 1`
		done
		set mv -- "$old" "$new"
		$debug && set simulate "$@"
		"$@"
		t="`qin "$new"` `qin "$old"`"
		echo "mv `dasher "$t"`" >& 5
		$debug && new=$old
	fi
	test ! -d "$new" && return
	ls -1A -- "$new" | while IFS= read -r fso
	do
		fso=$new/$fso
		test ! -e "$fso" && continue
		process "$fso"
	done
}

qin() {
	if test -z "$1"
	then
		echo '""'
		return
	fi
	local out= s="$1" p q
	while test -n "$s"
	do
		if q="`expr x"$s" : x"\([^\\\']*[\\\']\)"`"
		then
			s=${s#"$q"}; p=${q%?}; q="\\"${q#"$p"}
		else
			p=$s; q=; s=
		fi
		if
			LC_CTYPE=POSIX expr x"$p" : x".*[^-_./,:=A-Za-z0-9]" \
				> /dev/null
		then
			out=$out"'$p'"$q
		else
			out=$out$p$q
		fi
	done
	println "$out"
}

dasher() {
	case $1 in
		-*) println "-- $1";;
		*) println "$1"
	esac
}

simulate() {
	local arg out=SIMULATION:
	for arg
	do
		out=$out' '`qin "$arg"`
	done
	println "$out" >& 2
}

mydir=`dirname -- "$0"`
myscript=`basename -- "$0"`
myscriptpath=$mydir/$myscript; myscriptpath=${myscriptpath#./}
test -f "$myscriptpath"
cdir=`pwd`
test x"`readlink -f -- "$mydir"`" = x"`readlink -f -- "$cdir"`"

now=`date '+%Y-%m-%d %H:%M:%S'`
ubase=`echo $now | tr -d :- | tr ' ' '_'`
ubase="$mydir/undo_rename_$ubase"; ubase=${ubase#./}
usuff=.sh
undo=$ubase$usuff
c=2
while test -e "$undo"
do
	undo=${ubase}_$c$usuff
	c=`expr $c + 1`
done
while :
do
	t=`mktemp -u ${TMPDIR:-/tmp}/${0##*/}.XXXXXXXXXX`
	mkfifo -m 600 -- "$t" && break
done
fifo=$t

{
	cat <<- .
	#! /bin/sh
	
	# Run this script in order to undo the renaming
	# operation performed on $now by running script
	# `qin "$myscriptpath"`.
.
	cat <<- '.' | cut -c 2-
	|
	|set -e
	|
	|inform() {
	|	xmessage "$1" 2> /dev/null || printf '%s\n' "$1" >& 2 || :
	|}
	|
	|trap 'test $? = 0 || inform "script $0 failed!"' 0
	|
	|# Undo the various rename operations.
.
	tac < "$fifo"
	t=`qin "$undo"`
	cat <<- .
	
	# Clean up and finish.
	rm `dasher "$t"`
	inform "Script $t completed its job successfully!"
.
} > "$undo" & helper=$!

exec 5> "$fifo"; redir5=true

ls -1A -- "$mydir" | while IFS= read -r fso
do
	test x"$fso" = x"$myscript" && continue
	fso=$mydir/$fso
	test ! -e "$fso" && continue
	process "$fso"
done
inform "Script $myscriptpath completed its job successfully!"
