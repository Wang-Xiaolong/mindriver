#!/usr/bin/env bash
usage_todo() { cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) [OPTION...] FILE...
Search for todo items within the notes in FILEs.
Arguments:
  -t, --type=TYPE      4 TYPEs supported: t(odo) d(one) i(ssue) and s(olved)
  -p, --priority=[re]  1-digit decimal or range.
                         _               Not care(nc)
                         \\\\d|'\\d'|[0-9]  Any decimal(any)
                         '[^\\d\\s]'       No priority: somaday/maybe(no)
                         3               One decimal
                         [2-5]           Decimal range
  -d, --date=[re]      8-digit date like 20230811, or 2023\\\\d*
  -c, --context=[re]   User defined context word
  -H, --follow-link
	EOF
}; [ -n "$hlp" ] && usage_todo && return
func_todo() { dargs "$@"; local wd pr dt ctx
	# Get the 1st word of the matched text
	wd=$(sed 's/^![[:space:]]*\([[:alnum:]_]\+\).*$/\1/' <<< "$6")
	[[ $wd =~ ^[0-9] ]] && { pr="${wd:0:1}"; wd="${wd:1}"; } || wd=''
	if [[ $wd =~ _[0-9]{5,9}$ ]]; then
		dt=$(sed 's/.*_\([0-9]\{5,9\}\)$/\1/' <<< "$wd")
		wd=$(sed 's/_[0-9]\{5,9\}$//' <<< "$wd")
	fi; [ -n "$wd" ] && ctx="$wd"
	local colon=$(color ":" "0;36") pre=$(color "${2%.mr}" "0;35")
	local as=$(i2as "$3" "$2"); [ -z "$as" ] && as="$3" || as="$3|$as"
	pre+="$colon"; pre+=$(color "$as" "0;33"); pre+="$colon"
	pre+=$(color "$4" "0;32"); pre+="$colon"
	local txt=$(sed -n "$5p" "$2") mtchd=$(esc4sed "$6")
	local cl=$(color "$6" "1;33"); cl=$(esc4sed "$cl")
	txt=$(sed "s/$mtchd/$cl/g" <<< "$txt")
	echo -e "$pr$colon$dt$colon$ctx$colon$pre $txt"
} # $1=type $2=file_path $3=note_id $4=note_ln $5=file_ln $6=matched_txt
mr_todo() { PARAMS=$(getopt -o t:p:c:d:H -l \
	type:,priority:,context:,due:,follow-link \
	-n 'mr_todo' -- "$@"); [ $? -ne 0 ] && err "$ERR_ARG" && return
	eval set -- "$PARAMS"; dargs "$@"
	local tp=t pr='\d' ctx=_ dt=_ flnk f ptrn; declare -a fs
	while : ; do case "$1" in --) shift; break;;
		-t|--type) tp="$2"; shift 2;;
		-p|--priority) case $2 in nc) pr=_;;
			any) pr='\d';; no) pr='[^\d\s]';;
			*) pr="$2";; esac; shift 2;;
		-c|--context) ctx="$2"; shift 2;;
		-d|--date) dt="$2"; shift 2;;
		-H|--follow-link) flnk=y; shift;;
		*) err "$ERR_OPT $1"; return;;
	esac; done
	case $tp in '') err 'No type specified.'; return;;
		t) if [ -z "$pr" ]; then err "Empty priority."; return
		   elif [[ "$pr" = _ ]]; then
			ptrn='(?<=^|\s)\!(\w+|\s.*$)'
		   else local pcd="$pr"
			if [[ "$ctx" = _ && "$dt" = _ ]]; then pcd+="\w*\b"
			elif [[ "$dt" = _ ]]; then pcd+="$ctx(\b|_)"
			elif [[ "$ctx" = _ ]]; then pcd+="\w*_$dt\b"
			else pcd+="${ctx}_$dt\b"
			fi; ptrn="(?<=^|\s)\!($pcd|\s*$pcd.*$)"
		   fi;;
		d)	:
			;;
		i)	:
			;;
		s)	:
			;;
		*) err "Type $tp not supported."; return;;
	esac; dv ptrn
	for f in "$@"; do
		[[ ! $f = *.mr ]] && f+=".mr"
		[[ ! -f "$f" ]] && { err "Not found $f."; return; }
		fs+=("$f")
	done
	if [[ "${#fs[@]}" -eq 0 ]]; then
		[ -f "$MR_FILE" ] && fs+=$(spath "$MR_FILE") || {
			err "No file specified."; return; }
	fi
	scheg "func_todo $tp" -P "$ptrn" "${fs[@]}"
}; mr_todo "$@"