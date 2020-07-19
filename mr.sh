#!/usr/bin/env bash

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

#=== PUBLIC FUNCTIONS ==========================================================
debug() { [ $debug == true ] && >&2 echo "$@"; }
vecho() { [ $verbose == true ] && echo "$@"; }
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

mr_init() {
	if [[ "$0" != *"bash" ]]; then # $0 is path of bash indicate
	# it runs in current shell (or source mode, ". mr.sh") to keep vars.
  		echo "init should be run in source mode: '. $0 init'"
		usage_init
		export MR_FILE=Hello
		return
	fi

	debug "mr_init($@) BASH_SOURCE=$BASH_SOURCE"
	PARAMS=$(getopt -o c:f: -l command:,file:,shell -n 'mr_init' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"
	local mr_cmd=mr; local shell=false
	while : ; do
		case "$1" in
		-c|--command) mr_cmd="$2"; shift 2;;
		--shell) shell=true; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	if [ -z $1 ]; then
		alias | grep $(basename $BASH_SOURCE)
		[ -n "$MR_FILE" ] && echo "MR_FILE=$MR_FILE"
		return
	fi
	local mr_file="$1"; shift; debug "mr_file=$mr_file"
	local message="$*"; debug "message=$message"
	
	local mr_sh=$(realpath $BASH_SOURCE); debug "mr_sh=$mr_sh"
	alias $mr_cmd="$mr_sh"; vecho "Command alias $mr_cmd was setup."
	alias ${mr_cmd}init=". $mr_sh init"
	alias ${mr_cmd}a="$mr_sh a"
	alias ${mr_cmd}l="$mr_sh l"
	alias ${mr_cmd}lv="$mr_sh l -v"
	alias ${mr_cmd}e="$mr_sh e"

	local mr_dir=$(dirname $mr_file); debug "mr_dir=$mr_dir"
	[ ! -d "$mr_dir" ] && mkdir -p "$mr_dir" &&\
		echo "Directory $mr_dir not exist, create it."
	export MR_FILE=$(realpath $mr_file); debug "MR_FILE=$MR_FILE"
	[ -n "$message" ] && mr_add "$message" &&\
		echo "Add to $mr_file: $message"

	[ $shell == true ] && mr_shell
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
	else
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
		tempf=$(mktemp -u -t mr.XXXXXXXX.mt)
		vim $tempf
		[ -f $tempf ] && message=$(cat $tempf) || return
		rm -f $tempf
		debug "message=$message"
	fi
	if [ -z $(echo $message | tr -d '[:space:]') ]; then # empty?
		echo "Empty message, cancel."
	elif [ -z "$append" ]; then
		datestr=$(date '+%Y%m%d%H%M')
		echo "$datestr<nF>${message//$'\n'/<nL>}" >> $mr_file
	else #append
		local old=$(sed -n -e "${append}p" $mr_file)
		[ -z "$old" ] && echo "No line#$append." && return
		local msg="${message//$'\n'/<nL>}"; debug "msg=$msg"
		sed -i -e "${append}c $old<nL>$msg" $mr_file
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
	local ln=$1; shift; debug "ln=$ln"
	local exps="$*"; debug "exps=$exps"

	[ ! -f "$mr_file" ] && echo "$mr_file not found!" && return
	local old=$(sed -n -e "${ln}p" $mr_file)
	[ -z "$old" ] && echo "Line $ln not found!" && return
	local old_ts=$(sed -e 's/\(^[0-9]\+<nF>\).*/\1/' <<< $old)
	local old_msg=$(sed 's/^[0-9]\+<nF>//' <<< $old)
	old_msg=${old_msg//<nL>/$'\n'}
	debug "old_ts=$old_ts old_msg=$old_msg"

	if [ -z "$exps" ]; then
		tempf=$(mktemp -u -t mr.XXXXXXXX.mt)
		echo "$old_msg" > $tempf
		vim $tempf
		[ -f $tempf ] && message=$(cat $tempf) || return
		rm -f $tempf
		debug "message=$message"
		local msg="${message//$'\n'/<nL>}"; debug "msg=$msg"
		[ "$old_msg" == "$message" ] && echo "Not modified." && return
		sed -i -e "${ln}c $old_ts$msg" $mr_file
	else
		local exp=""
		for arg in "$@"; do
			exp="$exp"$'\n'"$arg"
		done
		debug "exp=$exp"
		sed -e "$exp" <<< $old_msg
		[ $? -ne 0 ] && return
		read -p "OK? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && return
		local new_msg=$(sed -e "$exp" <<< $old_msg)
		new_msg=${new_msg//$'\n'/<nL>}
		sed -i -e "${ln}c $old_ts$new_msg" $mr_file
	fi
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
	PARAMS=`getopt -o n -l mono -n 'mr_list' -- "$@"`
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"
	debug "mr_list($@)"
	local mono=false
	while : ; do
		case "$1" in
		-n|--mono) mono=true; shift;;
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
	if(verbose == "true")
		gsub(/<nL>/,"\n",msg);
	else
		gsub(/<nL>.*/,"...",msg);
	dt = substr($1,3)
	if(mono == "true")
		print "["dt"]"NR"\t"msg;
	else
		print "\033[0;32m["dt"]\033[0;36m"NR"\033[0m\t"msg;
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
	init) shift; [ $help_me == true ] && usage_init || mr_init "$@";;
	a|add) shift; [ $help_me == true ] && usage_add || mr_add "$@";;
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

# process help & verbose & debug in 1 place
args=() # empty array
help_me=false; verbose=false; debug=false
for arg in "$@"; do
	case "$arg" in
	'-?'|-h|--help) help_me=true;; # ? is a wildcard if not br by ''
	-v|--verbose) verbose=true;;
	--debug) debug=true; verbose=true;;
	*) args+=("$arg");; # collect args other than help/verbose/debug
	esac
done

if [[ $help_me == false && "$1" != init && "$1" != cd ]]; then
# help_me will always be processed (because showing help need nearly nothing)
# init will always be processed
# other commands need at least a working dir, and should run in child shell
	if [[ "$0" == *"bash" ]]; then # source mode: `. mr.sh` or source mr.sh`
		echo "mr* command should not run in source mode."
		return # exit in source mode will exit the shell
	fi # common (non-source) mode below
	if [[ -z "$MR_FILE" ]]; then
		echo "No dir specified with MR_FILE."
		echo "Please run '. $0 init' first."
		usage_init
		exit 0
	fi
fi

[ -z $(command -v getopt) ] && echo "No getopt command." && exit 1
process_command "${args[@]}"
