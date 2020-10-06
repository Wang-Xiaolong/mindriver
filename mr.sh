#!/usr/bin/env bash
[[ $_ != $0 ]] && mr_sourced=true # script is being sourced
#=== Functions for Sourced Mode ================================================
# BKM: only "$@" can trans args properly, $@/$*/"$*" can't.
debug() { [ "$debug" = true ] && >&2 echo "$@"; }
home_path() { [[ $1 =~ ^$HOME.* ]] && echo "~${1#$HOME}" || echo "$1"; }
norm_path() { # $1=path
	local abs=$(home_path $(realpath "$1"))
	local rel=$(realpath --relative-to="$PWD" "$1")
	[ ${#rel} -lt ${#abs} ] && echo "$rel" || echo "$abs"
}
mrREPO=''
get_repo() { # $1=path
	local dir=$(realpath "$1")
	while [ "$dir" != / ]; do
		[ -f "$dir/.mrc" ] && mrREPO="$dir" && return
		dir=$(dirname "$dir"); debug "dir=$dir"
	done; mrREPO=''
}
mrFILE=''
a2f() { # arg->file, $1=path|id|alias, return to mrFILE: 0=found 1=new 2=fail
	mrFILE=''
	[ -z "$1" ] && return 2
	[ -f "$1" ] && mrFILE="$1" && return 0
	local dir; [ -d "$1" ] && dir="$1" || dir=$(dirname "$1")
	debug "dir=$dir"
	[ ! -d "$dir" ] && echo "$dir is not a valid directory." && return 2
	get_repo "$dir"; debug "mrREPO=$mrREPO"
	[ -z "$mrREPO" ] && echo "$dir is not in a repository." && return 2
	eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc");
	debug "MR_REPO_EXT=$MR_REPO_EXT"
	[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT set, exit." && return 2
	if [ -d "$1" ]; then
		mrFILE="$1/.$MR_REPO_EXT"; debug "$1->$1/.$MR_REPO_EXT"
		[ -f "$1/.$MR_REPO_EXT" ] && return 0 || return 1
	fi
	[ -f "$1.$MR_REPO_EXT" ] && mrFILE="$1.$MR_REPO_EXT" && return 0
	local base=$(basename "$1"); debug "base=$base"
	if [ "$base" = + ]; then
		local max=$(find -H "$mrREPO" -type f \
			-regex ".*[./][0-9]+\.$MR_REPO_EXT" \
			-printf "%f\n" | grep -o "[0-9]\+\.$MR_REPO_EXT" \
			| sed "s/.$MR_REPO_EXT//" | sort -n | tail -1)
		debug "max=$max"
		[ -z "$max" ] && base=1 || base=$(( $max + 1 ))
		mrFILE="$dir/$base.$MR_REPO_EXT"; return 1
	fi
	[[ "$base" =~ ^[0-9]+$ ]] && local re=".*[./]$base.$MR_REPO_EXT" \
		|| local re=".*/$base\.[0-9]+\.$MR_REPO_EXT"; debug "re=$re"
	local found=$(find -H "$mrREPO" -type f -regex "$re")
	debug "found=$found"
	if [ -z "$found" ]; then
		if [[ "$base" =~ ^[0-9]+$ ]]; then
			mrFILE="$dir/$base.$MR_REPO_EXT"; return 1
		else
			echo "No alias '$base'."; return 2
		fi
	fi
	local lc=$(wc -l <<< "$found"); debug "lc=$lc"
	[ $lc -gt 1 ] && echo "Conflict! Multiple files found:" \
		&& echo "$found" && return 2
	mrFILE="$found"; return 0
}
#=== Sourced: NONE and CLEAN ===================================================
usage_sourced() {
	cat<<-EOF
Usage: . $(basename ${BASH_SOURCE[0]}) [OPTION]...
       . $(basename ${BASH_SOURCE[0]}) clean
       . $(basename ${BASH_SOURCE[0]})
When this script is called with "sourced mode", i.e. run within current shell,
it will prepare the environment to run other commands, according to OPTIONs,
or clean or display the environment.
	EOF
}
unvar() { # BKM: clean variables and functions from current shell
	unset mr_sourced arg a mr_aliases mr_params file
	unset debug mrREPO mrFILE
	unset -f debug home_path norm_path get_repo a2f usage_sourced unvar
}
if [ "$mr_sourced" = true ]; then
	if [ $# -eq 0 ]; then
		echo "Command alias:"
		alias | grep $(basename ${BASH_SOURCE[0]})
		echo "Current file: ${MR_FILE#$PWD/}"
		unvar; return
	fi
	for arg do # BKM: remove arg from $@
		shift
		case $arg in
			'-?'|-h|--help) usage_sourced; unvar; return;;
			--debug) debug=true;;
			*) set -- "$@" "$arg";;
		esac
	done; [ "$debug" = true ] && >&2 printf 'arg: %s\n' "$@"
	if [ "$1" = clean ]; then
		if [ -n "$MR_SH" ]; then
			mr_aliases=$(alias | grep "$MR_SH" \
				| sed -e 's/=.*//' -e 's/alias //')
			while IFS= read -r a ; do
				[ -z "$a" ] && continue
				unalias $a; echo "Unalias $a"
			done <<< "$mr_aliases"
		fi
		export -n MR_SH MR_FILE
		[ -n "$MR_PS1" ] && PS1="$MR_PS1" && unset MR_PS1
		unvar; return
	fi
	mr_params=$(getopt -o c:f:p -l command:,file:,ps1 -n 'mr_src' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && unvar && return
	eval set -- "$mr_params"
	while : ; do
		case "$1" in
		-c|--command) export MR_SH="$(realpath ${BASH_SOURCE[0]})"
			alias $2="$MR_SH"
			echo "Command alias '$2' was setup."
			shift 2;;
		-f|--file) file="$2"; shift 2;;
		-p|--ps1) [ -z "$MR_PS1" ] && MR_PS1="$PS1"
			PS1='$($MR_SH ps1)'; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; unvar; return;;
		esac
	done
	[ -z "$MR_SH" ] && echo "Error: No -c CMD, no command to use."
	[ -z "$file" ] && unvar && return
	a2f "$file"; [ $? -ne 0 ] && unvar && return
	export MR_FILE=$(realpath $mrFILE)
	echo "Current file: $(norm_path $MR_FILE)"
	unvar; return
fi
#=== PS1 =======================================================================
mr_ps1() {
	local repo='' prepo='' path="$(home_path $PWD)" file='' frepo='' out=''
	get_repo "$PWD"
	if [ -n "$mrREPO" ]; then
		prepo="$mrREPO"
		path=$(realpath --relative-to="$mrREPO" "$PWD")
		if [ "$path" = . ]; then
			path='' repo="$PWD"
		elif [[ "$PWD" =~ ^.*$path$ ]]; then
			repo=${PWD%$path}
		else
			repo="$mrREPO"
		fi
		out+="\033[0;32m$(home_path $repo)"
	fi
	[ -n "$path" ] && out+="\033[0;33m$path"
	if [ -n "$MR_FILE" ] && [ -f "$MR_FILE" ]; then
		get_repo "$MR_FILE"
		if [ -n "$mrREPO" ]; then
			eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc")
			[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT" && return
			file=$(realpath --relative-to="$mrREPO" "$MR_FILE")
			file=${file%.$MR_REPO_EXT}
			[ -z "$file" ] && file=.
			[ "$prepo" != "$mrREPO" ] && frepo="$mrREPO"
		else
			file=$(norm_path "$MR_FILE")
		fi
		out="\033[0;35m$file $out"
		[ -n "$frepo" ] && out="\033[0;31m$(norm_path $frepo)/$out"
	fi
	out+="\033[0m\n$ "
	printf "$out"
}
#=== INIT ======================================================================
usage_init() {
	cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) init [OPTION]... [DIRECTORY]
Create an empty MindRiver repository or reinitialize an existing one,
in a DIRECTORY, or if not provided, the working directory.
Basically a .mrc file with configurations specified in OPTIONs:
  -n, --name=NAME    Set the NAME of the repository.
  -o, --owner=OWNER  Set the name of the OWNER of the repository.
  -e, --email=EMAIL  Set the EMAIL address of the owner.
  -x, --ext=EXT      Set the EXTension of the thread file, by default it's 'mr',
                     meaning *.mr will be treated as MindRiver thread files.
		     Change it here if 'mr' has conflict with your system.
  -t, --temp=TEMP    Set the default extension of the TEMPorary file abstracted
                     from the thread when a message is being editted.
		     It's for the text editor to use your favorite highlighting.
		     'marktree' is the default option for a vim plug-in of mine:
		     https://github.com/Wang-Xiaolong/vim-marktree
	EOF
}
set_conf() { # $1=fp $2=key $3=value
	[ ! -f "$1" ] && echo "$2='$3'" >> "$1" && return
	[ -z $(grep "$2=" "$1") ] && echo "$2='$3'" >> "$1" && return
	sed -i "s/\($2=\).*/\1'$3'/" "$1"
}
mr_init() {
	PARAMS=$(getopt -o n:o:e:x:t: -l name:,owner:,email:,ext:,temp:\
		-n 'mr_init' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_init($@)"
	local name='' owner='' email='' ext='' temp='' dir='' conf=''
	while : ; do
		case "$1" in
		-n|--name) name="$2"; shift 2; debug "name=$append";;
		-o|--owner) owner="$2"; shift 2; debug "owner=$owner";;
		-e|--email) email="$2"; shift 2; debug "email=$email";;
		-x|--ext) ext="$2"; shift 2; debug "ext=$ext";;
		-t|--temp) temp="$2"; shift 2; debug "temp=$temp";;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ $# -gt 1 ] && echo 'Too many arguments.' && return
	[ $# -eq 1 ] && dir="$1" || dir=.
	[ ! -d "$dir" ] && echo "$dir is not a valid directory." && return
	get_repo "$dir"
	if [ -n "$mrREPO" ]; then
		echo "$dir is already in a repo($mrREPO)."
		cat "$mrREPO/.mrc"
		[ -z "$name$owner$email$ext$temp" ] && return
		read -p "Configure the repo with your values(y/n)? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
		conf="$mrREPO/.mrc"
		echo "Updating configuration:"
	else # create new repo
		conf="$dir/.mrc"
		[ -z "$ext" ] && ext=mr
		[ -z "$temp" ] && temp=marktree
		echo "Creating MindRiver repository:"
	fi
	[ -n "$name" ] && set_conf "$conf" MR_REPO_NAME "$name"
	[ -n "$owner" ] && set_conf "$conf" MR_REPO_OWNER "$owner"
	[ -n "$email" ] && set_conf "$conf" MR_REPO_EMAIL "$email"
	[ -n "$ext" ] && set_conf "$conf" MR_REPO_EXT "$ext"
	[ -n "$temp" ] && set_conf "$conf" MR_REPO_TEMP "$temp"
	cat "$conf"
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
edit_msg() { # $1=old_msg $2=file_path
	local ln1=$( head -n1 <<< "$1") type=''
	if [[ "$ln1" =~ ^[[:punct:]]*\<.*\.[a-z]+\> ]]; then
		type=$(sed 's/^[[:punct:]]*<.*\(\.[a-z]\+\)>.*$/\1/'<<<"$ln1")
	elif [ -n "$2" ]; then
		get_repo "$2"
		if [ -n "$mrREPO" ]; then
			eval $(grep 'MR_REPO_TEMP=' "$mrREPO/.mrc")
			[ -n "$MR_REPO_TEMP" ] && type=".$MR_REPO_TEMP"
		fi
	fi
	local tempf=$(mktemp -u -t mr.XXXXXXXX$type)
	[ -n "$1" ] && echo "$1" > $tempf
	vim $tempf
	[ -f $tempf ] && mrMSG=$(cat $tempf) || return 1
	rm -f $tempf
	[ -n "$1" ] && [ "$1" = "$mrMSG" ] && echo "No change." && return 2
	return 0
}
set_msg() { # $1=msg, if omitted, use $mrMSG; based on mrLOG
	local msg; [ -n "$1" ] && msg="$1" || msg="$mrMSG"
	local nomsg=$(get_nomsg)
	echo "$nomsg${msg//$'\n'/<nL>}"
}
set_date() { # $1=date
	sed "s/^[0-9]*/$1/" <<< "$mrLOG"
}
append_msg() { # $1=msg, if omitted, use $mrMSG; based on mrLOG
	local msg; [ -n "$1" ] && msg="$1" || msg="$mrMSG"
	echo "$mrLOG<nL>${msg//$'\n'/<nL>}"
}
update_log() { # $1=file $2=ln $3=log or mrLOG if omitted
	local log; [ -n "$3" ] && log="$3" || log="$mrLOG"
	sed -i "$2d" "$1"
	echo "$log" >> "$1"
	sort -o "$1" -n -t '<' -k1 "$1"
}
#=== ADD =======================================================================
usage_add() {
	cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) add [OPTION]... [MESSAGE]...
Add MESSAGE to the working thread. If no MESSAGE provided,
the text EDITOR will be launched to edit a complex message.
  -a, --append=MSG_ID  Append the MESSAGE to the tail of an existing message
                       specified by the MSG_ID.
  -e, --editor=EDITOR  Launch the EDITOR instead of the default one or the
                       pre-defined one.
  -f, --file=FILE      Specify the thread FILE to be added to.
  -i, --id=ID          Specify the thread FILE by it's ID number.
	EOF
}
mr_add() {
	PARAMS=$(getopt -o a:f:d: -l append:,file:,date: -n 'mr_add' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_add($@)"
	local append='' f='' date=''
	while : ; do
		case "$1" in
		-a|--append) append="$2"; shift 2; debug "append=$append"
			[[ ! $append =~ ^[0-9]+$ ]] && echo \
				"$append is not a number." && return;;
		-f|--file) f="$2"; shift 2; debug "f(ile)=$f";;
		-d|--date) date="$2"; shift 2; debug "date=$date"
			date=$(date -d "$date" '+%s')
			[ $? -ne 0 ] && return;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	local message="$*"; debug "message=$message"

	local file=''
	if [ -n "$f" ]; then
		a2f "$f"; [ $? -eq 2 ] && return
		file="$mrFILE"
	else
		[ ! -f "$MR_FILE" ] && echo "No $MR_FILE!" && return
		file="$MR_FILE"
	fi
	[ -z "$file" ] && echo "No file specified!" && return

	if [ -n "$append" ]; then
		if [ ! -f "$file" ]; then
			echo "No line#$append for no file."; return
		fi
		lc=$(wc -l "$file" | cut -d " " -f1); debug "lc=$lc"
		if (( $append > $lc )) || (( $append < 1 )); then
			echo "No line#$append."; return
		fi
	elif [ ! -f "$file" ]; then
		read -p "$file will be created, OK(y/n)? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
	fi

	if [ -z "$message" ]; then
		edit_msg '' "$file" #->mrMSG
		[ $? -ne 0 ] && return; debug "mrMSG=$mrMSG"
		message=$mrMSG
	fi
	if [ -z $(echo $message | tr -d '[:space:]') ]; then # empty?
		echo "Empty message, cancel."
	elif [ -z "$append" ]; then
		[ -z "$date" ] && date=$(date '+%s')
		echo "$date<nF>${message//$'\n'/<nL>}" >> $file
		sort -o "$file" -n -t '<' -k1 "$file"
	else #append
		get_log "$file" $append
		[ $? -ne 0 ] && return
		mrLOG=$(append_msg "$message")
		update_log "$file" $append
	fi
}
#=== ALIAS =====================================================================
usage_alias() {
	cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) alias [-d] [FILE] [ALIAS]
Set the alias for a specified file.
  -d, --delete  Delete the alias.
	EOF
}
set_alias() { # $1=file $2=alias
	a2f "$1"; [ $? -ne 0 ] && echo "$1 not found." && return
	local dir=$(dirname $mrFILE) base=$(basename $mrFILE) file="$mrFILE"
	[[ ! $base =~ ^(.*\.){0,1}[0-9]+\.[0-9a-zA-Z]+$ ]] && return
	if [ -n "$2" ]; then
		a2f "$2"; [ $? -eq 0 ] && \
			echo "Alias $2 already used by $mrFILE" && return
		base=$(sed "s/\(.*\.\)\{0,1\}\([0-9]\+\.[0-9a-zA-Z]\+\)"\
"/$2\.\2/" <<< "$base")
	else
		base=$(sed "s/\(.*\.\)\{0,1\}\([0-9]\+\.[0-9a-zA-Z]\+\)/\2/"\
			<<< "$base")
	fi
	[ "$file" != "$dir/$base" ] && mv "$file" "$dir/$base"\
		&& echo "$file->$base"
}
mr_alias() {
        PARAMS=$(getopt -o d -l delete -n 'mr_alias' -- "$@")
        [ $? -ne 0 ] && echo "Failed parsing the arguments." && return
        eval set -- "$PARAMS"; debug "mr_alias($@)"
	local delete=false
        while : ; do
                case "$1" in
                -d|--delete) delete=true; shift;;
                --) shift; break;;
                *) echo "Unknown option: $1"; return;;
                esac
        done
        if [ $# -eq 0 ]; then # no arg, print all alias files
		echo "todo"
	elif [ $# -eq 1 ]; then # $1=file, print it's alias, or delete if -d
		if [ $delete = true ]; then
			set_alias "$1"
		else
			echo "todo"
		fi
	elif [ $# -eq 2 ]; then # $1=file $2=alias, set alias
		set_alias "$1" "$2"
	else
		echo "Too many arguments for alias command."
	fi
}
#=== VIEW ======================================================================
usage_view() {
	cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) view [OPTION]... [ROW]...
Arguments:
  -f, --file=FILE
  -l, --linenum
	EOF
}

mr_view() {
	PARAMS=$(getopt -o f:mn -l file:,mono,number -n 'mr_view' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_view($@)"
	local mr_file=$MR_FILE mono=false num=false
	while : ; do
		case "$1" in
		-f|--file) a2f "$2"; [ $? -ne 0 ] && echo "$2 not found." \
			&& return; mr_file="$mrFILE"; shift 2;;
		-m|--mono) mono=true; shift;;
		-n|--number) num=true; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ ! -f "$mr_file" ] && echo "No file ${mr_file#$PWD/}" && return
	[ $# -eq 0 ] && echo "No row# specified." && return
	lc=$(wc -l "$mr_file" | cut -d ' ' -f1)
	for a in "$@"; do
		[[ ! "$a" =~ ^[0-9]+$ ]] && echo "$a is not a number." && return
		[ "$a" -gt "$lc" ] || [ "$a" -eq 0 ] \
			&& echo "$a is out of range." && return
		get_log "$mr_file" $a
		[ $? -ne 0 ] && return
		local ts=$(get_ts) msg=$(get_msg)
		ts=$(date -d "@$ts" "+[%Y-%m-%d (ww%U.%w) %H:%M:%S]")
		[ $mono = true ] && echo "$ts $a" \
			|| echo -e "\033[0;32m$ts \033[0;36m$a\033[0m"
		[ ! $num = true ] && echo "$msg" && continue
		mlc=$(wc -l <<< "$msg"); debug "mlc=$mlc(len:${#mlc})"
		[ $mono = true ] && e="%-${#mlc}s" \
			|| e="\\033[0;33m%-${#mlc}s\\033[0m"
		echo "$msg" | awk "{printf \"$e %s\\n\", NR, \$0}"
	done
}
#=== EDIT ======================================================================
usage_edit() {
	cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) edit [OPTION]... MSG_ID [EXPRESSION]...
Edit a message in a thread, specialized by the MSG_ID.
  -f, --file  Sepcify the thread file.
	EOF
}

mr_edit() {
	PARAMS=$(getopt -o f:d: -l file:date: -n 'mr_edit' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_edit($@)"
	local mr_file=$MR_FILE date=''
	while : ; do
		case "$1" in
		-f|--file) a2f "$2"; [ $? -ne 0 ] && echo "$2 not found." \
			&& return; mr_file="$mrFILE"; shift 2;;
		-d|--date) date="$2"; shift 2; debug "date=$date"
			date=$(date -d "$date" '+%s')
			[ $? -ne 0 ] && return;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ ! -f "$mr_file" ] && echo "$mr_file doesn't exist." && return
	[ -z "$1" ] && echo "No log# specified!" && return
	local ln=$1; shift; debug "ln=$ln"
	local exps="$*"; debug "exps=$exps"

	get_log "$mr_file" $ln
	[ $? -ne 0 ] && return; debug "mrLOG=$mrLOG"
	local msg=$(get_msg); debug "msg=$msg"

	if [ -n "$exps" ]; then
		local exp=""
		for arg in "$@"; do
			exp="$exp"$'\n'"$arg"
		done; debug "exp=$exp"
		mrMSG=$(sed -e "$exp" <<< $msg)
		[ $? -ne 0 ] && return
		echo "The result log would be:"; echo "$mrMSG"
		read -p "OK(y/n)? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
		mrLOG=$(set_msg); debug "mrLOG=$mrLOG"
	elif [ -z "$date" ]; then
		edit_msg "$msg" "$mr_file" #->mrMSG
		[ $? -ne 0 ] && return; debug "mrMSG=$mrMSG"
		mrLOG=$(set_msg); debug "mrLOG=$mrLOG"
	fi
	[ -n "$date" ] && mrLOG=$(set_date $date)
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
		-f|--file) a2f "$2"; [ $? -ne 0 ] && echo "$2 not found." \
			&& return; mr_file="$mrFILE"; shift 2;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ -z "$mr_file" ] && echo "No file specified." && return
	local args=( $@ ); debug "args=${args[@]}"
	local len=${#args[@]}; debug "len=$len"
	[ "$len" -lt 2 ] && echo "Not enough arguments." && return
	local dest=${args[$len-1]}; debug "dest=$dest"
	a2f "$dest"; [ $? -eq 2 ] && return
	dest=$(norm_path "$mrFILE")
	if [ ! -f "$dest" ]; then
		read -p "Create $dest, OK(y/n)? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
	fi
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
	[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
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
/./ {
	if (length(fr) != 0) { if ($1 < fr) next }
	if (length(to) != 0) { if ($1 > to) next }
	msg = $2
	if(v == "true") {
		dt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<ED><nL>.*/, "...", msg);
		gsub(/<nL>/,"\n",msg);
		sep = "\n";
	} else {
		dt = strftime("%m/%d %H:%M", $1);
		gsub(/<nL>.*/,"...",msg);
		gsub(/<mt.*>/,"",msg);
		sep = " "
	}
	if(n == "true")
		head = dt" "NR;
	else
		head = "\033[0;32m"dt" \033[0;33m"NR"\033[0m";
	print head""sep""msg;
}' "$1"; return 0
}

mrLOGS=''
mr_log_collect() { # $1=files #2=dir $3=from $4=to $5=kw
	debug "mr_log_collect("$@")"
	local dir=$2 sep=''; [[ "$dir" != */ ]] && dir="$dir/"
	while IFS= read -r mr_file; do
		[ ! -f "$mr_file" ] && continue
		local fn=${mr_file#$dir}; fn=${fn%.$MR_REPO_EXT}; debug "fn=$fn"
		local rs=$(awk -v fn="$fn" -v fr="$3" -v to="$4" '
BEGIN { FS="<nF>" }
/./ {
	if (length(fr) != 0) { if ($1 < fr) next }
	if (length(to) != 0) { if ($1 > to) next }
	print $1"<nF>"fn"<nF>"NR"<nF>"$2
}' "$mr_file")
		[ -n "$rs" ] && mrLOGS+="$sep""$rs" && sep=$'\n'
	done <<< "$1"
}

mr_log_dir() { # $1=file $2=verbose $3=mono $4=from $5=to
	debug "mr_log_dir($@)"
	get_repo "$1"
	[ -z "$mrREPO" ] && echo "$1 is not in a MindRiver repo." && return 0
	eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc")
	[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT set, exit." && return 0
	local mr_files=$(find -H $1 -name "*.$MR_REPO_EXT")
	mr_log_collect "$mr_files" "$1" "$4" "$5" ''
	echo "$mrLOGS" | sort -n -t '<' -k1 | awk -v v="$2" -v n="$3" '
BEGIN { FS="<nF>" }
/./ {
	msg = $4
	if(v == "true") {
		dt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<ED><nL>.*/, "...", msg)
		gsub(/<nL>/,"\n",msg);
		sep = "\n";
	} else {
		dt = strftime("%m/%d %H:%M", $1);
		gsub(/<nL>.*/,"...",msg);
		gsub(/<mt.*>/,"",msg);
		sep = " "
	}
	if(n == "true")
		head = dt" "$2"."$3;
	else
		head = "\033[0;32m"dt" \033[0;36m"$2" \033[0;33m"$3"\033[0m";
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
	[ -d "$f" ] && mr_log_dir "$f" $v $n "$fr" "$to" && return
	a2f "$f"; [ $? -eq 0 ] && \
		mr_log_file "$mrFILE" $v $n "$fr" "$to" && return
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
	PARAMS=$(getopt -o nvd:s:rR \
		-l mono,verbose,date:,sort:,reverse,recursive \
		-n 'mr_list' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_list($@)"
	local n=false v=false fr='' to='' d="." s="" r='' R=false
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
		-s|--sort) case "$2" in
			l|lt|last) s='-n -k2.4,2';;
			m|mt|mtime) s='-n -k1,1';;
			i|id) s='-n -k3.4,3';;
			d|dir) s='-k5.4,5 -k3.4,3n';;
			--) break;;
			*) echo "Unknown sort key word: $2"; return;;
			esac; shift 2;;
		-r|--reverse) r='-r'; shift;;
		-R|--recursive) R=true; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ $# -gt 1 ] && echo "Support only 1 file or dir." && return
	[ $# -eq 1 ] && d=$1
	[ ! -d "$d" ] && echo "$d is not a directory." && return
	get_repo "$d"; [ -z "$mrREPO" ] && echo "$d is not in a repo." && return
	eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc")
	[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT set, exit." && return
	local depth='-maxdepth 1'; [ $R = true ] && depth=''
	local files=$(find -H "$d" $depth -regex ".*[/.][0-9]+.$MR_REPO_EXT")
	[[ $d != */ ]] && d="$d/"
	if [ -z "$s" ]; then # no sort, fast output
		while IFS= read -r f; do
			[ -z "$f" ] || [ ! -f "$f" ] && continue
			local fn=${f#$d}
			fn=$(sed "s/^\(.*\/\)\{0,1\}\(\(.*\)\.\)\{0,1\}"\
"\([0-9]\+\)\.$MR_REPO_EXT$/-v id=\4 -v as=\3 -v dir=\1/" <<< "$fn")
			awk -v v=$v -v n=$n $fn '
BEGIN { FS="<nF>" }
/./ {
	if (NR == 1) {
		title = $2; ln = 1; lt = $1; lm = ""
	} else {
		if ($2 ~ /<FN>.*/) {
			title = $2
		} else {
			ln = NR; lt = $1; lm = $2
		}
	}
}
END {
	if(as == "")
		idas = id
	else
		idas = id"."as
	if(dir == "." || dir == "")
		dir = ""
	else
		dir = dir"# "
	gsub(/<nL>.*/, "", title)
	gsub(/^<FN>/, "", title)
	if(v == "true") {
		lt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", lt)
		gsub(/<ED><nL>.*/, "...", lm)
		gsub(/<nL>/, "\n", lm)
		sep = "\n"
	} else {
		lt = strftime("%m/%d %H:%M", lt)
		gsub(/<nL>.*/, "...", lm)
		gsub(/<mt.*>/, "", lm)
		sep = " "
	}
	if(n == "true")
		head = lt" "idas" "dir""title" #"lc
	else {
		head = "\033[0;32m"lt" \033[0;35m"idas" \033[0;33m"dir
		head = head"\033[0;36m"title" \033[0;33m#"ln"\033[0m"
	}
	print head""sep""lm
}' "$f"
		done <<< "$files"
		return
	fi
	local lines=''
	while IFS= read -r f; do
		debug "0.$(date +%s.%N)"
		[ -z "$f" ] || [ ! -f "$f" ] && continue
		local fn=${f#$d};
		debug "0.1.$(date +%s.%N) fn=$fn"
		fn=$(sed "s/^\(.*\/\)\{0,1\}\(\(.*\)\.\)\{0,1\}\([0-9]\+\)"\
"\.$MR_REPO_EXT$/\4<nF>\3<nF>\1/" <<< "$fn")
		debug "1.$(date +%s.%N) fn=$fn"
		local mt=$(date -r "$f" "+%s")
		lines+=$(awk -v mt=$mt -v fn=$fn '
BEGIN { FS="<nF>" }
/./ {
	if (NR == 1) {
		title = $2; ln = 1; lt = $1; lm = ""
	} else {
		if ($2 ~ /<FN>.*/) {
			title = $2
		} else {
			ln = NR; lt = $1; lm = $2
		}
	}
}
END { gsub(/^<FN>/, "", title)
print mt"<nF>"lt"<nF>"fn"<nF>"ln"<nF>"title"<nF>"lm }
' "$f")$'\n'
		debug "4.$(date +%s.%N)"
	done <<< "$files"; debug "lines=$lines"
	echo "$lines" | sort -t '<' $s $r | awk -v v=$v -v n=$n '
BEGIN { FS="<nF>" }
/./ {
	if (length(fr) != 0) { if ($7 < fr) next }
	if (length(to) != 0) { if ($7 > to) next }
	lm = $8
	if($4 == "")
		idas = $3
	else
		idas = $3":"$4
	if($5 == "." || $5 == "")
		dir = ""
	else
		dir = $5"# "
	ln = $6
	title = $7
	gsub(/<nL>.*/,"",title)
	if(v == "true") {
		lt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $2)
		gsub(/<ED><nL>.*/, "...", lm)
		gsub(/<nL>/, "\n", lm)
		sep = "\n"
	} else {
		lt = strftime("%m/%d %H:%M", $2)
		gsub(/<nL>.*/, "...", lm)
		gsub(/<mt.*>/, "", lm)
		sep = " "
	}
	if(n == "true")
		head = lt" "idas" "dir""title" #"ln
	else {
		head = "\033[0;32m"lt" \033[0;35m"idas" \033[0;33m"dir
		head = head"\033[0;36m"title" \033[0;33m#"ln"\033[0m"
	}
	print head""sep""lm
}'
}
#=== MAIN ======================================================================
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
[ $# -eq 0 ] && echo "Current File: $(norm_path $MR_FILE)" && exit
help=false debug=false
for arg do # BKM: remove arg from $@
	shift
	case $arg in
		'-?'|-h|--help) help=true;;
		--debug) debug=true;;
		*) set -- "$@" "$arg";;
	esac
done; [ "$debug" = true ] && >&2 printf 'arg: %s\n' "$@"
[ $# -eq 0 ] && usage && return 0  #No arg, show usage
case "$1" in  # Command
ps1) mr_ps1;;
init) shift; [ "$help" = true ] && usage_init || mr_init "$@";;
a|add) shift; [ "$help" = true ] && usage_add || mr_add "$@";;
alias) shift; [ "$help" = true ] && usage_alias || mr_alias "$@";;
v|view) shift; [ "$help" = true ] && usage_view || mr_view "$@";;
e|ed|edit) shift; [ "$help" = true ] && usage_edit || mr_edit "$@";;
m|mv|move) shift; [ "$help" = true ] && usage_move || mr_move "$@";;
l|log) shift; [ "$help" = true ] && usage_log || mr_log "$@";;
ls|list) shift; [ "$help" = true ] && usage_list || mr_list "$@";;
help) usage;;
*) local dir=$(dirname ${BASH_SOURCE[0]}) cmd=$1; shift
	if [ -f "$dir/mr.$cmd.sh" ]; then
		. "$dir/mr.$cmd.sh" "$@"
	else
		echo "Incorrect command: $cmd"
		usage
	fi;;
esac
