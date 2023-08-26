#!/usr/bin/env bash
usage_export() { cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) [OPTION]... ADDRESS...
Export one or more notes to text file or html page. (file.id.alias in pwd)
Arguments:
  -f, --file=<path>         Specify the file to locate the notes to be exported.
  -w, --html[=[+-][color]]  Export each note to html file.
                            + means to keep the text file
                              rather than delete it by default
	EOF
}; [ -n "$hlp" ] && usage_export && return
export_note() { dargs "$@"; assert -n "$1" -a -n "$2" -a -n "$3"
	local fn="${2/%.mr}.$1" as=$(i2as "$1" "$2")
	[[ -n "$as" && ! "$as" =~ \.[a-zA-Z0-9]+$ ]] && as="$as.marktree"
	[ -n "$as" ] && fn="$fn.$as" || fn="$fn.marktree"
	if [ -f "$fn" ]; then
		read -p "$fn already exist, ovwerwrite it?(y/n) " -n 1 -r
		[[ $REPLY =~ ^[Yy]$ ]] && echo || { echo; return; }
	fi
	local msg=$(i2txt "$1" "$2")
	echo "$msg" > "$fn"; echo "$fn is written."
	if [ -n "$4" ]; then
		[[ "$4" =~ ^([+-])?(.*)$ ]] || return
		local plus=${BASH_REMATCH[1]} cs=${BASH_REMATCH[2]}; dv plus cs
		[ -z "$cs" ] && vim -c "TOhtml" -cwqa "$fn" || \
			vim -c "colorscheme $cs" -c "TOhtml" -cwqa "$fn"
		[ ! "$plus" = '+' ] && rm -f "$fn"
	fi; return 0 #wo this func return non0 when plus' not +
} # $1=idx $2=file $3=nc $4=html
mr_export() { PARAMS=$(getopt -o f:w:: -l file:,html:: \
	-n 'mr_export' -- "$@"); [ $? -ne 0 ] && err "$ERR_ARG" && return
	eval set -- "$PARAMS"; dargs "$@"
	local file="$MR_FILE" html='' arg lc
	while : ; do case "$1" in --) shift; break;;
		-f|--file) file="$2"; shift 2;;
		-w|--html) [ -z "$2" ] && html='-' || html="$2"; shift 2;;
		*) err "$ERR_OPT $1"; return;;
	esac; done
	[ $# -eq 0 ] && err "No address specified." && return
	[ -z "$file" ] && err "No file specified." && return
	[[ $file != *.mr ]] && file="$file.mr"
	[ ! -f "$file" ] && err "$file not exist." && return
	local nc=$(f2nc "$file"); dbg "$file exist with $nc lines."
	iter_adws "$*" "$file" $nc export_note "$html"
}; mr_export "$@"
