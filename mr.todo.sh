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
  -L, --follow-link
  -k, --key=KEYDEF     Sort via a key. Will be passed to sort command.
	EOF
}; [ -n "$hlp" ] && usage_todo && return
func_todo() { dargs "$@"; local wd pr dt ctx
	# Get the 1st word of the matched text
	wd=$(sed 's/^[[:blank:]]*![[:blank:]]*\([[:alnum:]_]\+\).*$/\1/' \
		<<< "$6")
	[[ $wd =~ ^[0-9] ]] && {
		pr=$(color "${wd:0:1}" "0;35"); wd="${wd:1}"; } || wd=''
	if [[ $wd =~ _[0-9]{5,9}$ ]]; then
		dt=$(sed 's/.*_\([0-9]\{5,9\}\)$/\1/' <<< "$wd")
		dt=$(color "$dt" "0;32")
		wd=$(sed 's/_[0-9]\{5,9\}$//' <<< "$wd")
	fi; [ -n "$wd" ] && ctx=$(color "$wd" "0;33")
	local colon=$(color ":" "0;36") pre=$(color "${2%.mr}" "0;35")
	local as=$(i2as "$3" "$2"); [ -z "$as" ] && as="$3" || as="$3|$as"
	pre+="$colon"; pre+=$(color "$as" "0;33"); pre+="$colon"
	pre+=$(color "$4" "0;32"); pre+="$colon"
	local txt=$(sed -n "$5p" "$2") mtchd=$(esc4sed "$6")
	[[ "$txt" =~ ^[[:blank:]]*\|[[:blank:]]+ ]] && return
	local cl=$(color "$6" "1;33"); cl=$(esc4sed "$cl")
	txt=$(sed "s/$mtchd/$cl/g" <<< "$txt")
	echo -e "$pr$colon$ctx$colon$dt$colon$pre$txt"
} # $1=type $2=file_path $3=note_id $4=note_ln $5=file_ln $6=matched_txt
mr_todo() { PARAMS=$(getopt -o t:p:c:d:Lk: -l \
	type:,priority:,context:,due:,follow-link,key: \
	-n 'mr_todo' -- "$@"); [ $? -ne 0 ] && err "$ERR_ARG" && return
	eval set -- "$PARAMS"; dargs "$@"
	local tp=t pr='\d' ctx=_ dt=_ flnk f ptrn k; declare -a fs
	while : ; do case "$1" in --) shift; break;;
		-t|--type) tp="$2"; shift 2;;
		-p|--priority) case $2 in nc) pr=_;;
			any) pr='\d';; no) pr='[^\d\s]';;
			*) pr="$2";; esac; shift 2;;
		-c|--context) ctx="$2"; shift 2;;
		-d|--date) dt="$2"; shift 2;;
		-L|--follow-link) flnk=y; shift;;
		-k|--key) k+=" -k $2"; shift 2;;
		*) err "$ERR_OPT $1"; return;;
	esac; done
	case $tp in '') err 'No type specified.'; return;;
		t) if [ -z "$pr" ]; then err "Empty priority."; return
		   elif [[ "$pr" = _ ]]; then
			ptrn='(^|(?<![{[(=\s&|])\s+)\!(\w+|\s.*$)'
		   else local pcd="$pr"
			if [[ "$ctx" = _ && "$dt" = _ ]]; then pcd+="\w*\b"
			elif [[ "$dt" = _ ]]; then pcd+="$ctx(\b|_)"
			elif [[ "$ctx" = _ ]]; then pcd+="\w*_$dt\b"
			else pcd+="${ctx}_$dt\b"
			fi; ptrn="(^|(?<![{[(=\s&|])\s+)\!($pcd|\s*$pcd.*$)"
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
	if [ -n "$flnk" ]; then
		for f in "${fs[@]}"; do f2flfs "$f"; done
		fs=("${mr_flfs[@]}")
	fi
	[ -n "$k" ] && scheg "func_todo $tp" -P "$ptrn" "${fs[@]}" \
		| sort -t':' $k || scheg "func_todo $tp" -P "$ptrn" "${fs[@]}"
}; mr_todo "$@"
