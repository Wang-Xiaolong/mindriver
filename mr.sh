#!/usr/bin/env bash
[[ $_ != $0 ]] && mr_sourced=true # script is being sourced
#=== Functions for Sourced Mode ================================================
# BKM: only "$@" can trans args properly, $@/$*/"$*" can't.
debug() { [ "$debug" = true ] && >&2 echo "$@"; return 0; }
# debug variable: dv a b c => a=1 b=2 c=3
dv() { local a; for a in "$@"; do debug "$a=${!a}"; done; }
# debug variable with linenum: dvl $LINENO a b c
dvl() { local l=$1 a; shift; for a in "$@"; do debug "$l: $a=${!a}"; done; }
# debug assign: 'da a b' => a="b" then print the assignment
# 'da a b $LINENO' print lnum: before the assignment
da() { local a="$1=\"$2\""; eval "$a"; [ -z "$3" ] && a="$3: $a"; debug "$a"; }
home_path() { [[ $1 =~ ^$HOME.* ]] && echo "~${1#$HOME}" || echo "$1"; }
norm_path() { # $1=path
	local abs=$(home_path $(realpath "$1"))
	local rel=$(realpath --relative-to="$PWD" "$1")
	[ ${#rel} -lt ${#abs} ] && echo "$rel" || echo "$abs"
}
mrREPO=''
p2r() { # path->repo, $1=path
	local dir=$(realpath "$1")
	while [ "$dir" != / ]; do
		[ -f "$dir/.mrc" ] && mrREPO="$dir" && return
		da dir $(dirname "$dir") $LINENO
	done; mrREPO=''
}
mrFILE=''
a2f() { # arg->file, $1=path|id|alias
	mrFILE='' # return to mrFILE: 0=found_file 1=new 2=found_dir >2=fail
	[ -z "$1" ] && return 3
	[ -f "$1" ] && da mrFILE "$1" $LINENO && return 0
	[[ "$1" == */ ]] && [ -d "$1" ] && da mrFILE "$1" $LINENO && return 2
	local dir=$(dirname "$1")
	[ ! -d "$dir" ] && echo "$dir is not a valid directory." && return 4
	p2r "$dir"
	[ -z "$mrREPO" ] && echo "$dir is not in a repository." && return 5
	eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc");
	[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT set, exit." && return 6
	local base=$(basename "$1"); dvl $LINENO dir mrREPO MR_REPO_EXT base
	local id='' alias='' re='' found=''
	if [[ $base =~ ^(.*\.){0,1}([0-9]+|\+)$ ]]; then
		id=$(sed 's/^\(.*\.\)\?\([0-9]\+\|+\)$/\2/' <<< "$base")
		alias=$(sed "s/\.\?$id$//" <<< "$base")
	else
		alias="$base"
	fi; dvl $LINENO id alias
	if [ -n "$alias" ]; then
		re=".*/$alias\.[0-9]+\.$MR_REPO_EXT"
		found=$(find -H "$mrREPO" -type f -regex "$re")
	fi
	if [ "$id" = + ]; then
		[ -n "$found" ] && echo "Alias '$alias' already exist: $found"\
			&& return 9
		local max=$(find -H "$mrREPO" -type f \
			-regex ".*[./][0-9]+\.$MR_REPO_EXT" \
			-printf "%f\n" | grep -o "[0-9]\+\.$MR_REPO_EXT" \
			| sed "s/.$MR_REPO_EXT//" | sort -n | tail -1); dv max
		[ -z "$max" ] && id=1 || id=$(( $max + 1 ))
		[ -n "$alias" ] && id="$alias.$id"
		da mrFILE "$dir/$id.$MR_REPO_EXT" $LINENO; return 1
	elif [[ "$id" =~ ^[0-9]+$ ]]; then
		re=".*[./]$id.$MR_REPO_EXT"
		local found2=$(find -H "$mrREPO" -type f -regex "$re")
		if [ -z "$found2" ]; then
			[ -n "$found" ] && echo \
				"Alias '$alias' already exist: $found" \
				&& return 10
			[ -n "$alias" ] && id="$alias.$id"
			da mrFILE "$dir/$id.$MR_REPO_EXT" $LINENO; return 1
		fi
		found="$found2"
	elif [ -z "$found" ]; then
		[ -d "$1" ] && da mrFILE "$1" $LINENO && return 2
		echo "No alias '$alias'."; return 7
	fi
	local lc=$(wc -l <<< "$found"); dv found lc
	[ $lc -gt 1 ] && echo "Conflict! Multiple files found:" \
		&& echo "$found" && return 8
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
	unset mr_sourced arg mr_aliases mr_params file
	unset debug mrREPO mrFILE
	unset -f debug dv dvl da
	unset -f home_path norm_path p2r a2f usage_sourced unvar
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
	p2r "$PWD"
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
		p2r "$MR_FILE"
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
		-n|--name) name="$2"; shift 2; dv name;;
		-o|--owner) owner="$2"; shift 2; dv owner;;
		-e|--email) email="$2"; shift 2; dv email;;
		-x|--ext) ext="$2"; shift 2; dv ext;;
		-t|--temp) temp="$2"; shift 2; dv temp;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ $# -gt 1 ] && echo 'Too many arguments.' && return
	[ $# -eq 1 ] && dir="$1" || dir=.
	[ ! -d "$dir" ] && echo "$dir is not a valid directory." && return
	p2r "$dir"
	if [ -n "$mrREPO" ]; then
		echo "$dir is already in a repo($mrREPO)."
		cat "$mrREPO/.mrc"
		eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc");
		if [ -n "$MR_REPO_EXT" ]; then
			local ids=$(find -H "$mrREPO" -type f -regex \
				".*[./][0-9]+\.$MR_REPO_EXT" -printf "%f\n" \
				| grep -o "[0-9]\+\.$MR_REPO_EXT" \
				| sed "s/.$MR_REPO_EXT//" | sort -n )
			printf "IDs Occupied: "; local prev=-2 single=true
			while IFS= read -r id; do
				if [ $id -ne $(($prev + 1)) ]; then
					if [ $prev -lt 0 ]; then
						printf "$id"
					elif [ $single = true ]; then
						printf " $id"
					else
						printf "..$prev $id"
					fi
					single=true
				else
					single=false
				fi
				prev=$id
			done <<< "$ids"; printf "..$prev"$'\n'
		fi
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
	mrLOG=$(sed -n -e "${2}p" $1); dv mrLOG
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
		p2r "$2"
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
		-a|--append) append="$2"; shift 2; dv append
			[[ ! $append =~ ^[0-9]+$ ]] && echo \
				"$append is not a number." && return;;
		-f|--file) f="$2"; shift 2; dv f;;
		-d|--date) date="$2"; shift 2; dv date
			date=$(date -d "$date" '+%s')
			[ $? -ne 0 ] && return;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	local message="$*"; dv message

	local file=''
	if [ -n "$f" ]; then
		a2f "$f"; [ $? -gt 1 ] && return
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
		lc=$(wc -l "$file" | cut -d " " -f1); dv lc
		if (( $append > $lc )) || (( $append < 1 )); then
			echo "No line#$append."; return
		fi
	elif [ ! -f "$file" ]; then
		read -p "$file will be created, OK(y/n)? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
	fi

	if [ -z "$message" ]; then
		edit_msg '' "$file" #->mrMSG
		[ $? -ne 0 ] && return; dv mrMSG
		message=$mrMSG
	fi
	message=$(sed -e 's/[[:space:]]*$//' <<< $message)
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
#=== CAT =======================================================================
usage_cat() {
	cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) cat [OPTION]... MSG_ID...
Concatenate message(s) specified by MSG_ID(s) to standard output.
Arguments:
  -f, --file=FILE  Specify the thread FILE.
  -m, --mono       Don't color the head line.
  -n, --number     Show line number before each line.
	EOF
}
mr_cat() {
	PARAMS=$(getopt -o f:mn -l file:,mono,number -n 'mr_cat' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_cat($@)"
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
Usage: $(basename ${BASH_SOURCE[0]}) edit [OPTION]... MSG_ID
Edit a message in a thread, specialized by the MSG_ID.
  -f, --file=FILE  Specify the thread FILE.
  -d, --date=DATE  Modify the DATE of the message.
  -s, --sed=EXPR   Modify the mmessage with sed using the EXPRession.
                   Allow specifying multiple expressions with multiple option.
  -q, --quiet      Don't ask for user confirmation when -s/-sed specified.
	EOF
}
mr_edit() {
	PARAMS=$(getopt -o f:d:s:q -l file:,date:,sed:,quiet \
		-n 'mr_edit' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_edit($@)"
	local mr_file=$MR_FILE date='' exp='' ln='' quiet=false
	while : ; do
		case "$1" in
		-f|--file) a2f "$2"; [ $? -ne 0 ] && echo "$2 not found." \
			&& return; mr_file="$mrFILE"; shift 2;;
		-d|--date) date="$2"; shift 2; dv date
			date=$(date -d "$date" '+%s')
			[ $? -ne 0 ] && return;;
		-s|--sed) exp="$exp"$'\n'"$2"; shift 2; dv exp;;
		-q|--quiet) quiet=true; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	[ ! -f "$mr_file" ] && echo "$mr_file doesn't exist." && return
	[ -z "$1" ] && echo "No log# specified!" && return
	ln="$1"

	get_log "$mr_file" $ln
	[ $? -ne 0 ] && return; dv mrLOG
	local msg=$(get_msg); dv msg

	if [ -z "$exp" ] && [ -z "$date" ]; then
		edit_msg "$msg" "$mr_file" #->mrMSG
		[ $? -ne 0 ] && return; dv mrMSG
	elif [ -n "$exp" ]; then
		mrMSG=$(sed -e "$exp" <<< $msg)
		[ $? -ne 0 ] && return
		if [ $quiet = false ]; then
			echo "The result log would be:"; echo "$mrMSG"
			read -p "OK(y/n)? " -n 1 -r
			[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
		fi
	fi
	mrLOG=$(set_msg); dv mrLOG
	[ -n "$date" ] && mrLOG=$(set_date $date)
	update_log "$mr_file" $ln
}
#=== REMOVE ====================================================================
usage_remove() {
	cat<<-EOF
Usage: mr remove [OPTION]... LN...
Remove log(s) specified by LN(s).

Arguments:
  -f, --file=FILE
	EOF
}
mr_remove() {
	PARAMS=$(getopt -o f: -l file: -n 'mr_remove' -- "$@")
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
	[ $? -eq 0 ] && echo "No log specified." && return 
	echo "These logs will be removed:"
	local d_sed='' sep=''
	for ln in "$@"; do
		dv ln
		local nr_awk=$(echo $ln | sed 's/\([0-9]\+\)/NR==\1/g')
		local dump_awk='BEGIN { FS="<nF>" }'" $nr_awk"'{
	dt = strftime("%m/%d %H:%M", $1);
	msg = $2
	gsub(/<nL>.*/,"...",msg);
	gsub(/<mt.*>/,"",msg);
	print "\033[0;32m"dt" \033[0;33m"NR"\033[0m\t"msg;}'
		dv dump_awk
		awk "$dump_awk" "$mr_file"
		d_sed+="$sep${ln}d"
		sep="; "
	done; dv p_sed
	read -p "OK(y/n)? " -n 1 -r
	[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
	sed -i "$d_sed" "$mr_file"
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
	local len=${#args[@]}; dv len
	[ "$len" -lt 2 ] && echo "Not enough arguments." && return
	local dest=${args[$len-1]}; dv dest
	a2f "$dest"; [ $? -gt 1 ] && return
	dest=$(norm_path "$mrFILE")
	if [ ! -f "$dest" ]; then
		read -p "Create $dest, OK(y/n)? " -n 1 -r
		[[ ! $REPLY =~ ^[Yy]$ ]] && echo && return; echo
	fi
	echo "These logs will be moved to $dest:"
	local lns=( ${args[@]:0:$len-1} ); debug "lns=${lns[@]}"
	local p_sed=''; local d_sed=''; local sep=''
	for ln in "${lns[@]}"; do
		dv ln
		local nr_awk=$(echo $ln | sed 's/\([0-9]\+\)/NR==\1/g')
		local dump_awk='BEGIN { FS="<nF>" }'" $nr_awk"'{
	dt = strftime("%m/%d %H:%M", $1);
	msg = $2
	gsub(/<nL>.*/,"...",msg);
	gsub(/<mt.*>/,"",msg);
	print "\033[0;32m"dt" \033[0;33m"NR"\033[0m\t"msg;}'
		dv dump_awk
		awk "$dump_awk" "$mr_file"
		p_sed+="$sep${ln}p"
		d_sed+="$sep${ln}d"
		sep="; "
	done; dv p_sed
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
  -s, --sort		SORT the records in the order of date.
  -r, --reverse		sort the records in the REVERSEd date order.
	EOF
}
mr_log() {
	PARAMS=$(getopt -o nvd:sr -l mono,verbose,date:,sort,reverse \
		-n 'mr_log' -- "$@")
	[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
	eval set -- "$PARAMS"; debug "mr_log($@)"
	local n=false v=false fr='' to='' sort=''
	while : ; do
		case "$1" in
		-n|--mono) n=true; shift;;
		-v|--verbose) v=true; shift;;
		-d|--date)
			if [[ "$2" == *..* ]]; then
				fr=$(sed -e 's/\.\..*//' <<< $2)
				to=$(sed -e 's/.*\.\.//' <<< $2)
				dv fr to
				fr=$(date -d "$fr" "+%s")
				[ $? -ne 0 ] && echo "Bad from date." && return
				to=$(date -d "$to" "+%s")
				[ $? -ne 0 ] && echo "Bad to date." && return
			else
				fr=$(date -d "$2" "+%D") # ->date
				[ $? -ne 0 ] && echo "Bad date." && return
				fr=$(date -d "$fr" "+%s")
				let to=$fr+86400
			fi; dv fr to
			shift 2;;
		-s|--sort) sort='-k1n'; shift;;
		-r|--reverse) sort='-k1nr'; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done

	local paths='' first='' only=true
	for f in "$@"; do
		a2f "$f"; [ $? -gt 2 ] && return
		if [ -d "$mrFILE" ] || [ -f "$mrFILE" ]; then
			paths+=" $mrFILE"
			[ -z "$first" ] && first="$mrFILE" || only=false
		fi
	done
	if [ -z "$paths" ]; then
		[ -z "$MR_FILE" ] && paths=. || paths="$MR_FILE"
		[ -z "$first" ] && first="$paths"
	fi
	if [ -z "$MR_REPO_EXT" ]; then
		p2r "$first"
		[ -z "$mrREPO" ] && echo "$first is not in a repo." && return
		eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc")
		[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT." && return
	fi

	local findex="find -H $paths -regex .*[./][0-9]+\.$MR_REPO_EXT"
	if [ -z "$sort" ]; then
		findex+=" -printf \"%p\t%p\n\" | sed \
\"s/^\(.*\/\)\(.*\.\)\{0,1\}\([0-9]\+\)\.$MR_REPO_EXT\t/\1\t\3\t/\" \
			| sort -k1 -k2n"
	fi
	local found=$(eval $findex) lines='' path dpath; dv findex found
	local awkex='BEGIN { FS="<nF>" }
/./ {
	if (length(fr) != 0) { if ($1 < fr) next }
	if (length(to) != 0) { if ($1 > to) next }
	msg = $0; gsub(/^[0-9]+<nF>/, "", msg)
	if (p == "false") { print $1"<nF>"dpath"<nF>"NR"<nF>"msg; next }
	if (v == "true") {
		dt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<ED><nL>.*/, "...", msg)
		gsub(/<nL>/,"\n",msg)
		sep = "\n";
	} else {
		if (systime() - $1 > 180*24*60*60)
			dt = strftime("%Y/%m/%d", $1)
		else
			dt = strftime("%m/%d %H:%M", $1)
		gsub(/<nL>.*/,"...",msg)
		gsub(/<mt.*>/,"",msg)
		sep = " "
	}
	if (n == "true") head = dt" #"NR
	else head = "\033[0;32m"dt" \033[0;33m"NR"\033[0m"
	if (length(dpath) != 0) {
		if (n == "true" ) print "File: "dpath
		else print "File: \033[0;35m"dpath"\033[0m"
		dpath = ""
	}
	print head""sep""msg;
}'
	while IFS='' read -r line || [ -n "$line" ]; do
		[ -z "$line" ] && continue
		if [ -z "$sort" ]; then
			IFS=$'\t' read -r -a fields <<< "$line"; dv line
			path="${fields[2]}"
		else
			path="$line"
		fi
		if [ $only = true ] && [ -d "$first" ]; then
			dpath=$(realpath --relative-to="$first" "$path")
		else
			dpath=$(norm_path "$path")
		fi
		dpath=${dpath%.$MR_REPO_EXT}
		[ -z "$sort" ] && awk -v fr=$fr -v to=$to -v p=true \
			-v dpath=$dpath -v v=$v -v n=$n "$awkex" "$path" \
			|| lines+=$(awk -v fr=$fr -v to=$to -v p=false \
			-v dpath=$dpath "$awkex" "$path")$'\n'
	done <<< "$found"
	[ -z "$sort" ] && return; dv lines reverse
	awk -v v=$v -v n=$n 'BEGIN { FS="<nF>" }
/./ {
	path = $2; ln = $3; msg = $4
	if(v == "true") {
		date = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<ED><nL>.*/, "...", msg)
		gsub(/<nL>/, "\n", msg)
		sep = "\n"
	} else {
		if (systime() - $1 > 180*24*60*60)
			date = strftime("%Y/%m/%d", $1)
		else
			date = strftime("%m/%d %H:%M", $1)
		gsub(/<nL>.*/, "...", msg)
		gsub(/<mt.*>/, "", msg)
		sep = " "
	}
	if(n == "true")
		head = date" "path" #"ln" "msg
	else {
		head = "\033[0;32m"date" \033[0;35m"path" \033[0;33m"ln"\033[0m"
	}
	print head""sep""msg
}' <<< $(sort -t '<' $sort <<< "$lines")
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
	local n=false v=false fr='' to='' depth='-maxdepth 1' sort='' r=''
	while : ; do
		case "$1" in
		-n|--mono) n=true; shift;;
		-v|--verbose) v=true; shift;;
		-d|--date)
			if [[ "$2" == *..* ]]; then
				fr=$(sed -e 's/\.\..*//' <<< $2)
				to=$(sed -e 's/.*\.\.//' <<< $2); dv fr to
				fr=$(date -d "$fr" "+%s")
				[ $? -ne 0 ] && echo "Bad from date." && return
				to=$(date -d "$to" "+%s")
				[ $? -ne 0 ] && echo "Bad to date." && return
			else
				fr=$(date -d "$2" "+%D") # ->date
				[ $? -ne 0 ] && echo "Bad date." && return
				fr=$(date -d "$fr" "+%s")
				let to=$fr+86400
			fi; dv fr to
			shift 2;;
		-s|--sort) sort=$2; shift 2;;
		-r|--reverse) r='r'; shift;;
		-R|--recursive) depth=''; shift;;
		--) shift; break;;
		*) echo "Unknown option: $1"; return;;
		esac
	done
	local paths='' first='' only=true
	for f in "$@"; do
		a2f "$f"; [ $? -gt 2 ] && return
		if [ -d "$mrFILE" ] || [ -f "$mrFILE" ]; then
			paths+=" $mrFILE"
			[ -z "$first" ] && first="$mrFILE" || only=false
		fi
	done
	if [ -z "$paths" ]; then
		paths=.; [ -z "$first" ] && first="$paths"
	fi
	if [ -z "$MR_REPO_EXT" ]; then
		p2r "$first"
		[ -z "$mrREPO" ] && echo "$first is not in a repo." && return
		eval $(grep 'MR_REPO_EXT=' "$mrREPO/.mrc")
		[ -z "$MR_REPO_EXT" ] && echo "No MR_REPO_EXT." && return
	fi; dv paths first mrREPO MR_REPO_EXT

	local printfex sedex sortex pi pr
	case "$sort" in
	'') printfex="%p\t%p\n" sortex="-k1$r -k2n$r" pi=2 pr=true
	sedex="s/^\(.*\/\)\(.*\.\)\{0,1\}\([0-9]\+\)\.$MR_REPO_EXT\t/\1\t\3\t/";;
	i|id) printfex="%f\t%p\n" sortex="-k1n$r" pi=1 pr=true
	sedex="s/^\(.*\.\)\{0,1\}\([0-9]\+\)\.$MR_REPO_EXT\t/\2\t/";;
	m|mt|mtime) printfex="%T@\t%p\n" sortex="-k1n$r" pi=1 pr=true;;
	t|title) pr=false; sortex2="-k3$r -f";;
	l|lt|last) pr=false; sortex2="-k1n$r";;
	--) break;;
	*) echo "Unknown sort key word: $2"; return;;
	esac; 

	local findex="find -H $paths $depth -regex .*[./][0-9]+\.$MR_REPO_EXT"
	[ -n "$printfex" ] && findex+=" -printf \"$printfex\""
	[ -n "$sedex" ] && findex+=" | sed \"$sedex\""
	[ -n "$sortex" ] && findex+=" | sort $sortex"
	local found=$(eval $findex); dv findex found
	local awkex='BEGIN { FS="<nF>" }
/./ {
	if (NR == 1) { title = $2; ln = 1; lt = $1; lm = "" }
	else {
		if ($2 ~ /<FN>.*/) { title = $2	}
		else { ln = NR; lt = $1; lm = $2 }
	}
}
END {
	if (length(fr) != 0) { if (lt < fr) exit }
	if (length(to) != 0) { if (lt > to) exit }
	gsub(/<nL>.*/, "", title)
	gsub(/^<FN>/, "", title)
	if(pr != "true") {
		print lt"<nF>"path"<nF>"title"<nF>"ln"<nF>"lm
		exit
	}
	if(v == "true") {
		lt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", lt)
		gsub(/<ED><nL>.*/, "...", lm)
		gsub(/<nL>/, "\n", lm)
		sep = "\n"
	} else {
		if (systime() - lt > 180*24*60*60)
			lt = strftime("%y/%m/%d", lt)
		else
			lt = strftime("%m/%d %H:%M", lt)
		gsub(/<nL>.*/, "...", lm)
		gsub(/<mt.*>/, "", lm)
		sep = " "
	}
	if(n == "true")
		head = lt" "path" "title" #"ln
	else {
		head = "\033[0;32m"lt" \033[0;35m"path
		head = head" \033[0;36m"title" \033[0;33m"ln"\033[0m"
	}
	print head""sep""lm
}' lines=''
	while IFS='' read -r line || [ -n "$line" ]; do
		[ -z "$line" ] && continue
		local fields path dpath
		if [ $pr = true ]; then
			IFS=$'\t' read -r -a fields <<< "$line"
			path="${fields[$pi]}"
		else
			path="$line"
		fi
		if [ $only = true ] && [ -d "$first" ]; then
			dpath=$(realpath --relative-to="$first" "$path")
		else
			dpath=$(norm_path "$path")
		fi
		dpath=${dpath%.$MR_REPO_EXT}; dv dpath pr
		[ $pr = true ] && awk -v path="$dpath" -v v=$v -v n=$n \
			-v pr=$pr -v fr=$fr -v to=$to "$awkex" $path \
			|| lines+=$(awk -v path="$dpath" -v pr=$pr -v fr=$fr \
			-v to=$to "$awkex" $path)$'\n'
	done <<< "$found"
	[ $pr = true ] && return
	awk -v v=$v -v n=$n 'BEGIN { FS="<nF>" }
/./ {
	path = $2; title = $3; ln = $4; lm = $5
	if(v == "true") {
		lt = strftime("[%Y-%m-%d (ww%U.%w) %H:%M:%S]", $1)
		gsub(/<ED><nL>.*/, "...", lm)
		gsub(/<nL>/, "\n", lm)
		sep = "\n"
	} else {
		if (systime() - $1 > 180*24*60*60)
			lt = strftime("%Y/%m/%d", $1)
		else
			lt = strftime("%m/%d %H:%M", $1)
		gsub(/<nL>.*/, "...", lm)
		gsub(/<mt.*>/, "", lm)
		sep = " "
	}
	if(n == "true")
		head = lt" "path""title" #"ln
	else {
		head = "\033[0;32m"lt" \033[0;35m"path
		head = head" \033[0;36m"title" \033[0;33m"ln"\033[0m"
	}
	print head""sep""lm
}' <<< $(sort -t '<' $sortex2 <<< "$lines")
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
as|alias) shift; [ "$help" = true ] && usage_alias || mr_alias "$@";;
c|cat) shift; [ "$help" = true ] && usage_cat || mr_cat "$@";;
e|ed|edit) shift; [ "$help" = true ] && usage_edit || mr_edit "$@";;
r|rm|remove) shift; [ "$help" = true ] && usage_remove || mr_remove "$@";;
m|mv|move) shift; [ "$help" = true ] && usage_move || mr_move "$@";;
l|log) shift; [ "$help" = true ] && usage_log || mr_log "$@";;
ls|list) shift; [ "$help" = true ] && usage_list || mr_list "$@";;
help) usage;;
*) dir=$(dirname ${BASH_SOURCE[0]}) cmd=$1; shift
	if [ -f "$dir/mr.$cmd.sh" ]; then
		. "$dir/mr.$cmd.sh" "$@"
	else
		echo "Incorrect command: $cmd"
		usage
	fi;;
esac
