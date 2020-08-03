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

		mr_params=$(getopt -o c:f: -l command:,file:,shell \
			-n 'mr_init' -- "$@")
		[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
		eval set -- "$mr_params";
		while : ; do
			case "$1" in
			-c|--command) mr_cmd="$2"; shift 2;;
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
			alias ${mr_cmd}l="$mr_sh l"
			alias ${mr_cmd}lv="$mr_sh l -v"
			alias ${mr_cmd}e="$mr_sh e"
			export MR_CMD=$mr_cmd
			echo "Command alias $mr_cmd was setup."
			unset mr_sh mr_cmd
		fi
		if [ -n "$mr_file" ]; then
			export MR_FILE=$(realpath $mr_file)
			echo "Set $MR_FILE."
			unset mr_file
		fi
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

#=== INIT ======================================================================
usage_init() {
	cat<<-EOF
Usage: . ${BASH_SOURCE[0]#$PWD/} init [OPTION]... FILE [MESSAGE]...
This command should be run in source mode before any other MindRiver command.
Arguments:
  -c, --command=CMD
      --shell
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
	PARAMS=`getopt -o f:l -l file:,linenum -n 'mr_view' -- "$@"`
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"
	debug "mr_view($@)"
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
	PARAMS=`getopt -o a:f: -l append:,file: -n 'mr_add' -- "$@"`
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"
	debug "mr_add($@)"
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
#=== EDIT ======================================================================
usage_edit() {
	cat<<-EOF
Usage: mr edit [OPTION]... LN [EXPRESSION]...
Arguments:
  -f, --file
	EOF
}

mr_edit() {
	debug "mr_edit($@)"
	PARAMS=$(getopt -o af: -l append,file: -n 'mr_init' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"
	local mr_file=$MR_FILE
	while : ; do
		case "$1" in
		-f|--file) mr_file=$2; shift 2;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
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
#=== LOG =======================================================================
usage_log() {
	cat<<-EOF
Usage: mr add [OPTION]... [FILE]...
Arguments:
  -n, --mono
	EOF
}

mr_log() {
	PARAMS=`getopt -o nv -l mono,verbose -n 'mr_list' -- "$@"`
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"
	debug "mr_list($@)"
	local mono=false; local verbose=false;
	while : ; do
		case "$1" in
		-n|--mono) mono=true; shift;;
		-v|--verbose) verbose=true; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ ! -f "$MR_FILE" ] && echo "$(basename $MR_FILE) is not created yet."\
		&& return
	cat $MR_FILE | awk -v verbose="$verbose" -v mono="$mono" '
BEGIN {
	FS="<nF>"
}
{
	msg = $2
	if(verbose == "true") {
		dt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<nL>/,"\n",msg);
		sep = "\n";
	} else {
		dt = strftime("%m/%d %H:%M", $1);
		gsub(/<nL>.*/,"...",msg);
		gsub(/<mt.*>/,"",msg);
		sep = "\t"
	}
	if(mono == "true")
		head = dt" "NR;
	else
		head = "\033[0;32m"dt" \033[0;36m"NR"\033[0m";
	print head""sep""msg;
}
	'
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
	init) shift; [ $help_me != true ] && echo "Not sourced."
		usage_init;;
	a|add) shift; [ $help_me == true ] && usage_add || mr_add "$@";;
	v|view) shift; [ $help_me == true ] && usage_view || mr_view "$@";;
	e|ed|edit) shift; [ $help_me == true ] && usage_edit || mr_edit "$@";;
	l|log) shift; [ $help_me == true ] && usage_log || mr_log "$@";;
	ls) shift; [ $help_me == true ] && usage_list || mr_list "$@";;
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
