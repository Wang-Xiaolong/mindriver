#!/usr/bin/env bash
usage_report() {
	cat<<-EOF
Usage: $(basename "$MR_SH") report DIRECTORY
Generate report from the files in the specified DIRECTORY.
  -f, --file  Sepcify the thread file.
	EOF
}
[ "$help_me" = "true" ] && usage_report && return

PARAMS=$(getopt -o d: -l date: -n 'mr_report' -- "$@")
[ $? -ne 0 ] && echo "Failed parsing the arguments." && return
eval set -- "$PARAMS"; debug "mr_log($@)"
fr='' to=''
while : ; do
	case "$1" in
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
[ $# -eq 0 ] && usage_report && return
[ $# -gt 1 ] && echo "Support only 1 file directory." && return
[ ! -d "$1" ] && echo "$1 is not a valid directory." && return

report_dir() { # $1=root $2=dir $3=fr $4=to
	local head="== ${2#$1/}" grepres NAME=''
	if [ -f "$2/.mrd" ]; then
		grepres=$(grep "NAME=" "$2/.mrd")
		if [ -n "$grepres" ]; then
			eval "$grepres"
			[ -n "$NAME" ] && head="== $NAME"
		fi
	fi

	local sedex='s/^\(.*\.\)\?\([0-9]\+\)\.mr/\2/'
	local files=$(find -H "$2" -maxdepth 1 -type f -name "*.mr" \
		-printf "%f\t%p\n" | sed "$sedex" | sort -k1n)
	while IFS='' read -r line || [ -n "$line" ]; do
		IFS=$'\t' read -r -a fields <<< "$line"
		local output=$(awk -v fr=$3 -v to=$4 '
BEGIN { FS="<nF>"; all_text="" }
/./ {
	if (NR == 1) { title = $2 }
	else {
		if ($2 ~ /<FN>.*/) { title = $2 }
	}
	gsub(/<FN>/, "", title)
	gsub(/<nL>.*/, "", title)

	if ($2 !~ /<FN>.*/) {
		date = strftime("##%m/%d", $1)
		if (length(fr) != 0) { if ($1 < fr) next }
		if (length(to) != 0) { if ($1 > to) next }
		text = $2
		gsub(/<ED><nL>.*/, "...", text)
		gsub(/<nL>/, "\n", text)
		all_text = all_text""date" "text"\n"
	}
}
END { if (all_text != "") { print "-- "title"\n"all_text }}' "${fields[1]}")
		[ -z "$output" ] && continue
		[ -n "$head" ] && echo "$head" && head=''
		echo "$output"
	done <<< "$files"
	local dir dirs=''
	for dir in $2/*; do
		[ ! -d "$dir" ] && continue
		if [ -f "$dir/.mrd" ]; then
			local SORT=''
			grepres=$(grep "SORT=" "$dir/.mrd")
			if [ -n "$grepres" ]; then
				eval "$grepres"
				if [ -n "$SORT" ]; then
					dirs+="$SORT"$'\t'"$dir"$'\n'
					continue
				fi
			fi
		fi
		dirs+="$(basename $dir)"$'\t'"$dir"$'\n'
	done; dv dirs
	[ -z "$dirs" ] && return
	dirs=$(echo "$dirs" | sort -k1); dv dirs
	while IFS='' read -r line || [ -n "$line" ]; do
		[ -z "$line" ] && continue
		IFS=$'\t' read -r -a fields <<< "$line"
		debug "fields=(${fields[0]}, ${fields[1]})"
		report_dir "$1" "${fields[1]}" "$3" "$4"
	done <<< "$dirs"
}
report_dir "$1" "$1" "$fr" "$to"
