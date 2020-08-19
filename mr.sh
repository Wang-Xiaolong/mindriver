#!/usr/bin/env bash
#=== Sourced: INIT and CLEAN ===================================================
if [[ $_ != $0 ]]; then # script is being sourced
	if [ $# -eq 0 ]; then
		./${BASH_SOURCE[0]#$PWD/}
		return
	fi
	orig_args=( "$@" )
	for arg do
		shift
		case $arg in
		'-?'|-h|--help) ./${BASH_SOURCE[0]#$PWD/} "${orig_args[@]}"
			unset orig_args; return;;
		--debug) mr_debug=true;;
		*) set -- "$@" "$arg";;
		esac
	done; unset orig_args
	[ "$mr_debug" == true ] && echo "Sourced mr: $@"

	if [ "$1" == init ]; then
		shift; [ "$mr_debug" == true ] && echo "mr_init()"
		if [ $# -eq 0 ]; then
			echo "Command alias:"
			alias | grep $(basename $BASH_SOURCE)
			echo "Current file: $MR_FILE"
		fi

		mr_params=$(getopt -o c:e:f: -l command:,ext:,file:,shell \
			-n 'mr_init' -- "$@")
		[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
		eval set -- "$mr_params"; debug "mr_init($@)"
		while : ; do
			case "$1" in
			-c|--command) mr_cmd="$2"; shift 2;;
			-e|--ext) export MR_EXT="$2"; shift 2;;
			-f|--file) mr_file="$2"; shift 2;;
			--shell) mr_shell=true; shift;;
			--) shift; break;;
			*) echo "Unknown option: $1"; return;;
			esac
		done
		if [ -n "$mr_cmd" ]; then
			mr_sh=$(realpath $BASH_SOURCE)
			alias $mr_cmd="$mr_sh"
			alias ${mr_cmd}init=". $mr_sh init"
			alias ${mr_cmd}f=". $mr_sh init -f"
			alias ${mr_cmd}clean=". $mr_sh clean"
			alias ${mr_cmd}a="$mr_sh a"
			alias ${mr_cmd}e="$mr_sh e"
			alias ${mr_cmd}m="$mr_sh m"
			alias ${mr_cmd}l="$mr_sh l"
			alias ${mr_cmd}lv="$mr_sh l -v"
			alias ${mr_cmd}ls="$mr_sh ls"
			export MR_CMD=$mr_cmd
			echo "Command alias $mr_cmd was setup."
			unset mr_sh mr_cmd
		fi
		if [ -n "$mr_file" ]; then
			export MR_FILE=$(realpath $mr_file)
			echo "Set $MR_FILE."
			unset mr_file
		fi
		[ -z "$MR_EXT" ] && echo "Warning: No -e EXT, no log/ls."
	elif [ "$1" == clean ]; then
		shift; [ $mr_debug == true ] && echo "mr_clean()"
		unalias ${MR_CMD} ${MR_CMD}init ${MR_CMD}clean ${MR_CMD}f
		unalias ${MR_CMD}a ${MR_CMD}l ${MR_CMD}lv unalias ${MR_CMD}e
		export -n MR_CMD MR_FILE
	else
		echo "Unsupported sourced mode command $1."
	fi
	return
fi
#=== PUBLIC FUNCTIONS ==========================================================
usage() {
	cat<<-EOF
Mind River, in which logs float down, 
Usage:
  . ${BASH_SOURCE[0]#$PWD/} init
  mr [-h|--help|-?]
  mr <command> [<args>]

The commands are:
  help          Show this document.
  init          Make the mr command available.
  a|add         Create a new record.
You can run 'mr <command> <-h|--help|-?>' to get the document of each command.
	EOF
}

debug() { [ $debug == true ] && >&2 echo "$@"; }
# only "$@" can trans args properly, $@/$*/"$*" can't.
str_trim() { echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

#=== INIT and CLEAN's usage ====================================================
usage_init() {
	cat<<-EOF
Usage: . ${BASH_SOURCE[0]#$PWD/} init [OPTION]...
This command should be "sourced".
Arguments:
  -c, --command=CMD
  -f, --file=FILE
      --shell
	EOF
}

usage_clean() {
	cat<<-EOF
Usage: . ${BASH_SOURCE[0]#$PWD/} clean
This command should be "sourced".
	EOF
}

#=== FILE ======================================================================
mrLOG=''
get_log() { # $1=file $2=ln return:0/1/2,mrLOG
	debug "get_log($1, $2)"
	[ ! -f "$1" ] && echo "$1 not found!" && return 1
	mrLOG=$(sed -n -e "${2}p" $1); debug "mrLOG=$mrLOG"
	[ -z "$mrLOG" ] && echo "Line $2 not found!" && return 2
	return 0
}
get_nomsg() { sed -e 's/\(^[0-9]\+<nF>\).*/\1/' <<< $mrLOG; }
get_ts() { sed -e 's/\(^[0-9]\+\).*/\1/' <<< $mrLOG; }
get_msg() { sed -e 's/^[0-9]\+<nF>//' -e 's/<nL>/\n/g' <<< $mrLOG; }
mrMSG=''
edit_msg() { # $1=old_msg
	local tempf=$(mktemp -u -t mr.XXXXXXXX.mt)
	[ -n "$1" ] && echo "$1" > $tempf
	vim $tempf
	[ -f $tempf ] && mrMSG=$(cat $tempf) || return 1
	rm -f $tempf
	[ -n "$1" ] && [ "$1" == "$mrMSG" ] && echo "No change." && return 2
	return 0
}
set_msg() { # $1=msg, if omitted, use $mrMSG; based on mrLOG
	local msg; [ -n "$1" ] && msg="$1" || msg="$mrMSG"
	local nomsg=$(get_nomsg)
	echo "$nomsg${msg//$'\n'/<nL>}"
}
append_msg() { # $1=msg, if omitted, use $mrMSG; based on mrLOG
	local msg; [ -n "$1" ] && msg="$1" || msg="$mrMSG"
	echo "$mrLOG<nL>${msg//$'\n'/<nL>}"
}
update_log() { # $1=file $2=ln $3=log or mrLOG if omitted
	local log; [ -n "$3" ] && log="$3" || log="$mrLOG"
	sed -i -e "$2c $log" $1
}
insert_log() { # $1=file  Insert mrLOG into the file
	local ts=$(get_ts)
	local ln=$(cat $1 | awk -v ts=$ts '
BEGIN {
	FS="<nF>"
}
{
	if ($1 > ts) {
		print NR;
		exit
	}
}
	'); debug "ln=$ln"
	if [ -n "$ln" ]; then
		sed -i -e "${ln}i $mrLOG" "$1"
	else
		echo "$mrLOG" >> "$1"
	fi
}
delete_log() { # $1=file $2=ln
	debug "1:$1 2:$2"
	sed -i -e "$2d" $1
	debug "deleted"
}
#=== ADD =======================================================================
usage_add() {
	cat<<-EOF
Usage: mr add [OPTION]... [MESSAGE]...
Arguments:
  -a, --append=LN
  -f, --file=FILE
	EOF
}

NUMRE='^[0-9]+$'

mr_add() {
	PARAMS=$(getopt -o a:f: -l append:,file: -n 'mr_add' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_add($@)"
	local append=""; local mr_file=$MR_FILE
	while : ; do
		case "$1" in
		-a|--append) append="$2"; shift 2; debug "append=$append";;
		-f|--file) mr_file="$2"; shift 2; debug "mr_file=$mr_file";;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	local message="$*"; debug "message=$message"

	if [ ! -f "$mr_file" ]; then
		echo "$mr_file not found, will be created."
		[ -n "$append" ] && echo "No line#$append." && return
	elif [ -n "$append" ]; then
		if [[ ! $append =~ $NUMRE ]]; then
			echo "$append is not a number."
			return
		fi
		lc=$(wc -l "$mr_file" | cut -d " " -f1); debug "lc=$lc"
		if (( $append > $lc )) || (( $append < 1 )); then
			echo "No line#$append."
			return
		fi
	fi

	if [ -z "$message" ]; then
		edit_msg #->mrMSG
		[ $? -ne 0 ] && return; debug "mrMSG=$mrMSG"
		message=$mrMSG
	fi
	if [ -z $(echo $message | tr -d '[:space:]') ]; then # empty?
		echo "Empty message, cancel."
	elif [ -z "$append" ]; then
		datestr=$(date '+%s')
		echo "$datestr<nF>${message//$'\n'/<nL>}" >> $mr_file
	else #append
		get_log "$mr_file" $append
		[ $? -ne 0 ] && return
		mrLOG=$(append_msg "$message")
		update_log "$mr_file" $append
	fi
}
#=== VIEW ======================================================================
usage_view() {
	cat<<-EOF
Usage: mr view [OPTION]... [LN]...
Arguments:
  -f, --file=FILE
  -l, --linenum
	EOF
}

mr_view() {
	PARAMS=$(getopt -o f:l -l file:,linenum -n 'mr_view' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_view($@)"
	local mr_file=$MR_FILE; local pr_ln=false;
	while : ; do
		case "$1" in
		-f|--file) file=$2; shift 2;;
		-l|--linenum) pr_ln=true; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	ln=$1

	get_log "$mr_file" $ln
	[ $? -ne 0 ] && return
	local ts=$(get_ts)
	local msg=$(get_msg)
	date -d "@$ts" "+[%Y-%m-%d (ww%U.%w) %H:%M:%S]"
	echo "$msg"
}
#=== EDIT ======================================================================
usage_edit() {
	cat<<-EOF
Usage: mr edit [OPTION]... LN [EXPRESSION]...
Arguments:
  -f, --file
	EOF
}

mr_edit() {
	PARAMS=$(getopt -o af: -l append,file: -n 'mr_init' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_edit($@)"
	local mr_file=$MR_FILE
	while : ; do
		case "$1" in
		-f|--file) mr_file=$2; shift 2;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ -z "$mr_file" ] && echo "No file specified." && return
	[ -z "$1" ] && echo "No log# specified!" && return
	local ln=$1; shift; debug "ln=$ln"
	local exps="$*"; debug "exps=$exps"

	get_log "$mr_file" $ln
	[ $? -ne 0 ] && return; debug "mrLOG=$mrLOG"
	local msg=$(get_msg); debug "msg=$msg"

	if [ -z "$exps" ]; then
		edit_msg "$msg" #->mrMSG
		[ $? -ne 0 ] && return; debug "mrMSG=$mrMSG"
	else
		local exp=""
		for arg in "$@"; do
			exp="$exp"$'\n'"$arg"
		done; debug "exp=$exp"
		mrMSG=$(sed -e "$exp" <<< $msg)
		[ $? -ne 0 ] && return
		echo "The result log would be:"; echo "$mrMSG"
		read -p "OK(y/n)? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && return
	fi
	mrLOG=$(set_msg); debug "mrLOG=$mrLOG"
	update_log "$mr_file" $ln
}
#=== MOVE ======================================================================
usage_move() {
	cat<<-EOF
Usage: mr move [OPTION]... LN... DEST
Move log(s) specified by LN(s) to the log file specified by DEST.

Arguments:
  -f, --file=FILE
	EOF
}

mr_move() {
	PARAMS=$(getopt -o f: -l file: -n 'mr_move' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_move($@)"
	local mr_file=$MR_FILE
	while : ; do
		case "$1" in
		-f|--file) mr_file=$2; shift 2;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ -z "$mr_file" ] && echo "No file specified." && return
	local args=( $@ ); debug "args=${args[@]}"
	local len=${#args[@]}; debug "len=$len"
	[ "$len" -lt 2 ] && echo "Not enough arguments." && return
	local dest=${args[$len-1]}; debug "dest=$dest"
	[ ! -f "$dest" ] && echo "$dest doesn't exist, will be created."
	echo "These logs will be moved to $dest:"
	local lns=( ${args[@]:0:$len-1} ); debug "lns=${lns[@]}"
	local p_sed=''; local d_sed=''; local sep=''
	for ln in "${lns[@]}"; do
		debug "ln=$ln"
		local nr_awk=$(echo $ln | sed 's/\([0-9]\+\)/NR==\1/g')
		local dump_awk='BEGIN { FS="<nF>" }'" $nr_awk"'{
	dt = strftime("%m/%d %H:%M", $1);
	msg = $2
	gsub(/<nL>.*/,"...",msg);
	gsub(/<mt.*>/,"",msg);
	print "\033[0;32m"dt" \033[0;36m"NR"\033[0m\t"msg;}'
		debug "dump_awk=$dump_awk"
		awk "$dump_awk" "$mr_file"
		p_sed+="$sep${ln}p"
		d_sed+="$sep${ln}d"
		sep="; "
	done; debug "p_sed=$p_sed"
	read -p "OK(y/n)? " -n 1 -r
	[[ ! $REPLY =~ ^[Yy]$ ]] && return
	sed -n "$p_sed" "$mr_file" >> "$dest"
	sort -o "$dest" -n -t '<' -k1 "$dest"
	sed -i "$d_sed" "$mr_file"
}
#=== LOG =======================================================================
usage_log() {
	cat<<-EOF
Usage: mr log [OPTION]... [FILE or DIRECTORY]
List the logs in a specified FILE or DIRECTORY.
Example:
	mr log example.log
	mr log path/to/directory

OPTIONs:
  -d, --date=DATE	set the range of DATE of the logs to be listed.
			DATE is a string accepted by command 'date -d',
			can can also be a range like DATE1..DATE2.
  -n, --mono		stop display color in the result.
  -v, --verbose		display verbose result.
	EOF
}

mr_log_file() { # $1=file $2=verbose $3=mono $4=from $5=to
	awk -v v="$2" -v n="$3" -v fr="$4" -v to="$5" '
BEGIN { FS="<nF>" }
{
	if (length(fr) != 0) { if ($1 < fr) next }
	if (length(to) != 0) { if ($1 > to) next }
	msg = $2
	if(v == "true") {
		dt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<nL>/,"\n",msg);
		sep = "\n";
	} else {
		dt = strftime("%m/%d %H:%M", $1);
		gsub(/<nL>.*/,"...",msg);
		gsub(/<mt.*>/,"",msg);
		sep = "\t"
	}
	if(n == "true")
		head = dt" "NR;
	else
		head = "\033[0;32m"dt" \033[0;36m"NR"\033[0m";
	print head""sep""msg;
}' "$1"; return 0
}

mrLOGS=''
mr_log_collect() { # $1=files #2=dir $3=from $4=to $5=kw
	debug "mr_log_collect("$@")"
	local dir=$2; [[ "$dir" != */ ]] && dir="$dir/"
	while IFS= read -r mr_file; do
		[ ! -f "$mr_file" ] && continue
		fn=${mr_file#$dir}; fn=${fn%.$MR_EXT}; debug "fn=$fn"
		mrLOGS+=$(awk -v fn="$fn" -v fr="$3" -v to="$4" '
BEGIN { FS="<nF>" }
{
	if (length(fr) != 0) { if ($1 < fr) next }
	if (length(to) != 0) { if ($1 > to) next }
	print $1"<nF>"fn"<nF>"NR"<nF>"$2
}' "$mr_file")
	done <<< "$1"
}

mr_log_dir() { # $1=file $2=verbose $3=mono $4=from $5=to
	debug "mr_log_dir($@)"
	[ -z "$MR_EXT" ] && echo "No EXT set, exit." && return 0
	local mr_files=$(find $1 -name "*.$MR_$MR_EXT")
	mr_log_collect "$mr_files" "$1" "$4" "$5" ''
	echo "$mrLOGS" | sort -n -t '<' -k1 | awk -v v="$2" -v n="$3" '
BEGIN { FS="<nF>" }
{
	msg = $4
	if(v == "true") {
		dt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<nL>/,"\n",msg);
		sep = "\n";
	} else {
		dt = strftime("%m/%d %H:%M", $1);
		gsub(/<nL>.*/,"...",msg);
		gsub(/<mt.*>/,"",msg);
		sep = " "
	}
	if(n == "true")
		head = dt" "$2"#"$3;
	else
		head = "\033[0;32m"dt" \033[0;36m"$2"#"$3"\033[0m";
	print head""sep""msg;
}'; return 0
}

mr_log() {
	PARAMS=$(getopt -o nvd: -l mono,verbose,date -n 'mr_log' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_log($@)"
	local n=false v=false fr='' to='' f="$MR_FILE"
	while : ; do
		case "$1" in
		-n|--mono) n=true; shift;;
		-v|--verbose) v=true; shift;;
		-d|--date)
			if [[ "$2" == *..* ]]; then
				fr=$(sed -e 's/\.\..*//' <<< $2)
				to=$(sed -e 's/.*\.\.//' <<< $2)
				debug "from=$fr; to=$to"
				fr=$(date -d "$fr" "+%s")
				[ $? -ne 0 ] && echo "Bad from date." && return
				to=$(date -d "$to" "+%s")
				[ $? -ne 0 ] && echo "Bad to date." && return
			else
				fr=$(date -d "$2" "+%D") # ->date
				[ $? -ne 0 ] && echo "Bad date." && return
				fr=$(date -d "$fr" "+%s")
				let to=$fr+86400
			fi; debug "from=$fr; to=$to"
			shift 2;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ $# -gt 1 ] && echo "Support only 1 file or dir." && return
	[ $# -eq 1 ] && f=$1
	[ -z "$f" ] && f='.'; debug "file=$f"
	[ -f "$f" ] && mr_log_file "$f" $v $n "$fr" "$to" && return
	[ -d "$f" ] && mr_log_dir "$f" $v $n "$fr" "$to" && return
	echo "$f doesn't exist."
}
#=== LIST ======================================================================
usage_list() {
	cat<<-EOF
Usage: mr list [OPTION]... [DIRECTORY]
List the log files in a DIRECTORY.
Example:
	mr list path/to/directory

OPTIONs:
  -d, --date=DATE	set the range of DATE of the logs to be listed.
			DATE is a string accepted by command 'date -d',
			can can also be a range like DATE1..DATE2.
  -n, --mono		stop display color in the result.
  -v, --verbose		display verbose result.
	EOF
}

mr_list() {
	PARAMS=$(getopt -o nvd:s: -l mono,verbose,date:,sort: \
		-n 'mr_list' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_list($@)"
	local n=false v=false fr='' to='' d="." s="-k1"
	while : ; do
		case "$1" in
		-n|--mono) n=true; shift;;
		-v|--verbose) v=true; shift;;
		-d|--date)
			if [[ "$2" == *..* ]]; then
				fr=$(sed -e 's/\.\..*//' <<< $2)
				to=$(sed -e 's/.*\.\.//' <<< $2)
				debug "from=$fr; to=$to"
				fr=$(date -d "$fr" "+%s")
				[ $? -ne 0 ] && echo "Bad from date." && return
				to=$(date -d "$to" "+%s")
				[ $? -ne 0 ] && echo "Bad to date." && return
			else
				fr=$(date -d "$2" "+%D") # ->date
				[ $? -ne 0 ] && echo "Bad date." && return
				fr=$(date -d "$fr" "+%s")
				let to=$fr+86400
			fi; debug "from=$fr; to=$to"
			shift 2;;
		-s|--sort)
			if [ "$2" == "l" ]; then
				s="-n -k3.4"
			elif [ "$2" == "m" ]; then
				s="-n -k2.4"
			else
				echo "Unsupported sort $s."
			fi
			shift 2;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ $# -gt 1 ] && echo "Support only 1 file or dir." && return
	[ $# -eq 1 ] && d=$1
	[ ! -d "$d" ] && echo "$d is not a directory." && return
	[ -z "$MR_EXT" ] && echo "No EXT set, exit." && return
	local files=$(find "$d" -name "*.$MR_EXT") lines=''
	[[ $d != */ ]] && d="$d/"
	while IFS= read -r f; do
		[ -z "$f" ] && continue
		[ ! -f "$f" ] && continue
		local fn=${f#$d}; debug "fn=$fn"
		local mt=$(date -r "$f" "+%s")
		local latest=$(tail -1 $f)
		[ -z "$latest" ] && lastest="$mt<nF>--FILE EMPTY--"
		lines+="$fn<nF>$mt<nF>$latest"$'\n'
	done <<< "$files"; debug "lines=$lines"
	echo "$lines" | sort -t '<' $s | awk -v v=$v -v n=$n '
BEGIN { FS="<nF>" }
/./ {
	if (length(fr) != 0) { if ($3 < fr) next }
	if (length(to) != 0) { if ($3 > to) next }
	msg = $4
	if(v == "true") {
		dt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $3)
		gsub(/<nL>/,"\n",msg)
		sep = "\n"
	} else {
		dt = strftime("%m/%d %H:%M", $3)
		gsub(/<nL>.*/,"...",msg)
		gsub(/<mt.*>/,"",msg)
		sep = " "
	}
	if(n == "true")
		head = dt" "$1
	else
		head = "\033[0;32m"dt" \033[0;36m"$1"\033[0m"
	print head""sep""msg
}'
}
#=== SHELL =====================================================================
usage_shell() {  #heredoc
	cat<<-EOF
Shell-like environment, where you can run gtd commands without typing 'gtd'.
	EOF
}

in_shell=false
process_command() {
	[ $# -eq 0 ] && usage && return 0  #No arg, show usage

	case "$1" in  #$1 is command
	init) [ $help_me != true ] && echo "Not sourced."; usage_init;;
	clean) [ $help_me != true ] && echo "Not sourced."; usage_clean;;
	a|add) shift; [ $help_me == true ] && usage_add || mr_add "$@";;
	v|view) shift; [ $help_me == true ] && usage_view || mr_view "$@";;
	e|ed|edit) shift; [ $help_me == true ] && usage_edit || mr_edit "$@";;
	m|mv|move) shift; [ $help_me == true ] && usage_move || mr_move "$@";;
	l|log) shift; [ $help_me == true ] && usage_log || mr_log "$@";;
	ls|list) shift; [ $help_me == true ] && usage_list || mr_list "$@";;
	sh|shell) [ $in_shell == false ] && mr_shell "$@"\
		|| echo "We are already in the mind river shell.";;
	exit) [ $in_shell == true ] && in_shell=false \
		|| echo "exit is a mind river shell command.";;
	help) usage;;
	version) echo "0.03 2020-06-15 paulo.dx@gmail.com";;
	*) echo "Incorrect command: $1"; usage;;
	esac
	return 0
}

mr_shell() {
	[ $help_me == true ] && usage_shell && return

	in_shell=true
	while : ; do # infinite loop
		printf "$(basename $MR_FILE)# "
		read args
		eval set -- "$args"
		process_command "$@"
		[ $in_shell == false ] && break
	done
}
#=== MAIN ======================================================================
[ $# -eq 0 ] && usage && exit # bkm for no arg check

# process help & debug before other options
args=() # empty array
help_me=false; debug=false
for arg in "$@"; do
	case "$arg" in
	'-?'|-h|--help) help_me=true;; # ? is a wildcard if not br by ''
	--debug) debug=true;;
	*) args+=("$arg");; # collect args other than help/debug
	esac
done

[ -z $(command -v getopt) ] && echo "No getopt command." && exit 1
process_command "${args[@]}"
