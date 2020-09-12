#!/usr/bin/env bash
#=== Sourced: NONE and CLEAN ===================================================
if [[ $_ != $0 ]]; then # script is being sourced
	if [ $# -eq 0 ]; then
		echo "Command alias:"
		alias | grep $(basename ${BASH_SOURCE[0]})
		echo "Current file: ${MR_FILE#$PWD/}"
		return
	fi
	for a in "$@"; do
		if [ "$a" = -? ] || [ "$a" = -h ] || [ "$a" = --help ]; then
			$(realpath ${BASH_SOURCE[0]}) "$@"; return
		fi
	done
	if [ "$1" = clean ]; then
		if [ -n "$MR_SH" ]; then
			mr_aliases=$(alias | grep "$MR_SH" \
				| sed -e 's/=.*//' -e 's/alias //')
			while IFS= read -r a ; do
				[ -z "$a" ] && continue
				unalias $a; echo "Unalias $a"
			done <<< "$mr_aliases"; unset mr_aliases
		fi
		export -n MR_SH MR_FILE
		return
	fi
	mr_params=$(getopt -o c:f: -l command:,file: -n 'mr_src' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$mr_params"
	while : ; do
		case "$1" in
		-c|--command) export MR_SH="$(realpath ${BASH_SOURCE[0]})"
			alias $2="$MR_SH"
			echo "Command alias '$2' was setup."
			shift 2;;
		-f|--file) file="$2"; shift 2;;
		--) shift; break;;
		*) echo "Unknown option: $1"; unset mr_params mr_id; return;;
		esac
	done; unset mr_params
	[ -z "$MR_SH" ] && echo "Error: No -c CMD, no command to use."
	[ -z "$file" ] && return
	if [ -f "$file" ]; then
		export MR_FILE="$file"; unset file
	else
		id=$file; unset file
		IFS=':' read -ra MR_ID <<< "$id"
		if [ ${#MR_ID[@]} -eq 1 ]; then
			id="${MR_ID[0]}" dir=.
		elif [ ${#MR_ID[@]} -eq 2 ]; then
			id="${MR_ID[1]}" dir="${MR_ID[0]}"
		else
			echo "Bad num of ':'s(${#MR_ID[@]}) in id!"
			unset MR_ID id; return
		fi; unset MR_ID
		[ -z "$id" ] && echo "Empty id!" \
			&& unset id dir && return
		[ ! -d "$dir" ] && echo "No directory $dir!" \
			&& unset id dir && return
		repo='' d=$(realpath "$dir")
		while [ "$d" != / ]; do
			[ -f "$d/.mrc" ] && repo="$d" && break
			d=$(dirname "$d")
		done; unset d
		[ -z "$repo" ] && echo "$dir is not in a repo" \
			&& unset id dir repo && return; unset dir
		eval $(grep 'MR_REPO_EXT=' "$repo/.mrc")
		[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT set!" \
			&& unset id repo && return
		[[ "$id" =~ ^[0-9]+$ ]] && re=".*[./]$id.$MR_REPO_EXT" \
			|| re=".*/$id\.[0-9]+\.$MR_REPO_EXT"
		unset id MR_REPO_EXT
		found=$(find "$repo" -regex "$re"); unset re repo
		[ -z "$found" ] && echo "File not found." \
			&& unset found && return
		lc=$(wc -l <<< "$found")
		[ $lc -gt 1 ] && echo "Conflict! Multiple files found:" \
			&& echo "$found" && unset found lc && return; unset lc
		export MR_FILE="$found"; unset found
	fi
	echo "Current file: ${MR_FILE#$PWD/}"
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

debug() { [ $debug = true ] && >&2 echo "$@"; }
# only "$@" can trans args properly, $@/$*/"$*" can't.
str_trim() { echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

#=== CLEAN's usage ============================================================
usage_clean() {
	cat<<-EOF
Usage: . ${BASH_SOURCE[0]#$PWD/} clean
This command should be "sourced".
	EOF
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
mrREPO=''
get_repo() { # $1=path
	local dir=$(realpath "$1")
	while [ "$dir" != / ]; do
		[ -f "$dir/.mrc" ] && mrREPO="$dir" && return
		dir=$(dirname "$dir"); debug "dir=$dir"
	done; mrREPO=''
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
		[[ ! $REPLY =~ ^[Yy]$ ]] && return
		conf="$mrREPO/.mrc"
		echo; echo "Updating configuration:"
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
edit_msg() { # $1=old_msg
	local type=''; [ -n "$MR_REPO_TEMP" ] && type=".$MR_REPO_TEMP"
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

NUMRE='^[0-9]+$'
mrFILE=''
arg2file() { # $1=arg, will set mrFILE, mrREPO and source mrREPO/.mrc
	mrFILE=''
	[ -z "$1" ] && return
	[ -f "$1" ] && mrFILE=$1 && return
	local id='' dir='' re=''
	IFS=':' read -ra MR_ID <<< "$1"
	if [ ${#MR_ID[@]} -eq 1 ]; then
		id="${MR_ID[0]}" dir=.
	elif [ ${#MR_ID[@]} -eq 2 ]; then
		id="${MR_ID[1]}" dir="${MR_ID[0]}"
	else
		echo "Bad num of ':'s(${#MR_ID[@]}) in id!"; return
	fi; unset MR_ID
	[ -z "$id" ] && echo "Empty id!" && return
	[ ! -d "$dir" ] && echo "No directory $dir" && return
	get_repo "$dir"
	[ -z "$mrREPO" ] && echo "$dir is not in a repo" && return
	source "$mrREPO/.mrc"
	[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT in the repo!" && return
	[[ "$id" =~ ^[0-9]+$ ]] && re=".*[./]$id.$MR_REPO_EXT" \
		|| re=".*/$id\.[0-9]+\.$MR_REPO_EXT"
	local found=$(find "$mrREPO" -type f -regex "$re")
	[ -z "$found" ] && echo "File not found." && return
	local lc=$(wc -l <<< "$found")
	[ $lc -gt 1 ] && echo "Conflict! Multiple files found:" \
		&& echo "$found" && return
	mrFILE="$found"
}
# arg2file with new file creation
arg2file_plus() { # $1=id, will set mrFILE, mrREPO and source mrREPO/.mrc
	mrFILE=''
	[ -z "$1" ] && return
	[ -f "$1" ] && mrFILE=$1 && return
	local id='' dir='' re=''
	IFS=':' read -ra MR_ID <<< "$1"
	if [ ${#MR_ID[@]} -eq 1 ]; then
		id="${MR_ID[0]}" dir=.
	elif [ ${#MR_ID[@]} -eq 2 ]; then
		id="${MR_ID[1]}" dir="${MR_ID[0]}"
	else
		echo "Bad num of ':'s(${#MR_ID[@]}) in id!"; return
	fi; unset MR_ID; debug "id=$id dir=$dir"
	[ -z "$id" ] && echo "Empty id!" && return
	[ ! -d "$dir" ] && echo "No directory $dir" && return
	get_repo "$dir"
	[ -z "$mrREPO" ] && echo "$dir is not in a repo" && return
	source "$mrREPO/.mrc"
	[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT in the repo!" && return
	if [ "$id" = + ]; then
		local max=$(find "$mrREPO" -type f \
			-regex ".*[./][0-9]+\.$MR_REPO_EXT" \
			-printf "%f\n" | grep -o "[0-9]\+\.$MR_REPO_EXT" \
			| sed "s/.$MR_REPO_EXT//" | sort -n | tail -1)
		debug "max=$max"
		[ -z "$max" ] && id=1 || id=$(( $max + 1 ))
		mrFILE="$dir/$id.$MR_REPO_EXT"
		return
	fi
	[[ "$id" =~ ^[0-9]+$ ]] && re=".*[./]$id.$MR_REPO_EXT" \
		|| re=".*/$id\.[0-9]+\.$MR_REPO_EXT"
	local found=$(find "$mrREPO" -type f -regex "$re")
	if [ -z "$found" ]; then
		if [[ "$id" =~ ^[0-9]+$ ]]; then
			echo "ID $id not found."
			read -p "Create a new file with it(y/n)? " -n 1 -r
			echo
			[[ ! $REPLY =~ ^[Yy]$ ]] && return
			mrFILE="$dir/$id.$MR_REPO_EXT"
		else
			echo "Alias '$id' not found."
		fi
		return
	fi
	local lc=$(wc -l <<< "$found")
	[ $lc -gt 1 ] && echo "Conflict! Multiple files found:" \
		&& echo "$found" && return
	mrFILE="$found"
}

mr_add() {
	PARAMS=$(getopt -o a:f: -l append:,file: -n 'mr_add' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_add($@)"
	local append='' f='' dir='.'
	while : ; do
		case "$1" in
		-a|--append) append="$2"; shift 2; debug "append=$append"
			[[ ! $append =~ $NUMRE ]] && echo \
				"$append is not a number." && return;;
		-f|--file) f="$2"; shift 2; debug "f(ile)=$f";;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	local message="$*"; debug "message=$message"

	local file=''
	if [ -n "$f" ]; then
		arg2file_plus "$f"; debug "mrFILE=$mrFILE"
		file="$mrFILE"
	else
		[ ! -f "$MR_FILE" ] && echo "No $MR_FILE!" && return
		file="$MR_FILE"
	fi
	[ -z "$file" ] && echo "No file specified!" && return

	if [ -n "$append" ]; then
		if [ ! -f "$file" ]; then
			echo "No line#$append for no file."
			return
		fi
		lc=$(wc -l "$file" | cut -d " " -f1); debug "lc=$lc"
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
		[ ! -f "$file" ] && echo "$file will be created."
		echo "$datestr<nF>${message//$'\n'/<nL>}" >> $file
	else #append
		get_log "$file" $append
		[ $? -ne 0 ] && return
		mrLOG=$(append_msg "$message")
		update_log "$file" $append
	fi
}
#=== VIEW ======================================================================
usage_view() {
	cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) view [OPTION]... [LN]...
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
Usage: $(basename ${BASH_SOURCE[0]}) edit [OPTION]... MSG_ID [EXPRESSION]...
Edit a message in a thread, specialized by the MSG_ID.
  -i, --id  Sepcify the thread file.
	EOF
}

mr_edit() {
	PARAMS=$(getopt -o i: -l id: -n 'mr_edit' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_edit($@)"
	local mr_file=$MR_FILE
	while : ; do
		case "$1" in
		-i|--id) id2file "$2"
			[ -z "$mrFILE" ] && echo "$2 not found." && return
			mr_file="$mrFILE"; shift 2;;
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
	local dir=$2 sep=''; [[ "$dir" != */ ]] && dir="$dir/"
	while IFS= read -r mr_file; do
		[ ! -f "$mr_file" ] && continue
		local fn=${mr_file#$dir}; fn=${fn%.$MR_EXT}; debug "fn=$fn"
		local rs=$(awk -v fn="$fn" -v fr="$3" -v to="$4" '
BEGIN { FS="<nF>" }
{
	if (length(fr) != 0) { if ($1 < fr) next }
	if (length(to) != 0) { if ($1 > to) next }
	print $1"<nF>"fn"<nF>"NR"<nF>"$2
}' "$mr_file")
		[ -n "$rs" ] && mrLOGS+="$sep""$rs" && sep=$'\n'
	done <<< "$1"
}

mr_log_dir() { # $1=file $2=verbose $3=mono $4=from $5=to
	debug "mr_log_dir($@)"
	[ -z "$MR_EXT" ] && echo "No EXT set, exit." && return 0
	local mr_files=$(find $1 -name "*.$MR_EXT")
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
			if [ "$2" = l ]; then
				s="-n -k3.4"
			elif [ "$2" = m ]; then
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
		local fn=${f#$d}; fn=${fn%.$MR_EXT}; debug "fn=$fn"
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
#=== MAIN ======================================================================
process_command() {
	[ $# -eq 0 ] && usage && return 0  #No arg, show usage

	case "$1" in  #$1 is command
	clean) [ $help_me != true ] && echo "Not sourced."; usage_clean;;
	init) shift; [ $help_me = true ] && usage_init || mr_init "$@";;
	a|add) shift; [ $help_me = true ] && usage_add || mr_add "$@";;
	v|view) shift; [ $help_me = true ] && usage_view || mr_view "$@";;
	e|ed|edit) shift; [ $help_me = true ] && usage_edit || mr_edit "$@";;
	m|mv|move) shift; [ $help_me = true ] && usage_move || mr_move "$@";;
	l|log) shift; [ $help_me = true ] && usage_log || mr_log "$@";;
	ls|list) shift; [ $help_me = true ] && usage_list || mr_list "$@";;
	help) usage;;
	version) echo "0.03 2020-06-15 paulo.dx@gmail.com";;
	*) echo "Incorrect command: $1"; usage;;
	esac
	return 0
}

[ $# -eq 0 ] && echo "Current File: $MR_FILE" && exit

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
