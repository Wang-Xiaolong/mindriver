#!/usr/bin/env bash
[[ $_ != $0 ]] && mr_sourced=true
#=== Debug Functions ==========================================================
calrln() { caller 1 | cut -d ' ' -f1; }; dbg=''
dbg() { [ -n "$dbg" ] && >&2 echo "$(calrln): $@"; }
dv() { [ -z "$dbg" ] && return; >&2 echo -n "$(calrln):"
	for a in "$@"; do >&2 echo -n " $a=${!a}"; done; >&2 echo; }
dt() { [ -z "$dbg" ] && return; local l="$(calrln)"
	for a in "$@"; do >&2 echo "$l ---- $a ----"; >&2 echo "${!a}"; done; }
dargs() { [ -z "$dbg" ] && return; >&2 echo -n "$(caller 0 | cut -d ' ' -f2)("
	d=''; for a in "$@"; do >&2 echo -n "$d$a"; d=', '; done; >&2 echo \); }
#=== Error Function & Messages =================================================
err() { >&2 echo "ERROR($(calrln)): $@"; }
erx() { >&2 echo "ERROR($(calrln)): $@"; exit; }
ERR_ARG='Failed to parse arguments.'
ERR_OPT='Unknown option:'
#=== Sourced: NONE and CLEAN ===================================================
usage_sourced() { cat<<-EOF
Usage: . $(basename ${BASH_SOURCE[0]}) [OPTION]...     <- Setup the environment
       . $(basename ${BASH_SOURCE[0]}) clean           <- Clean the environment
       . $(basename ${BASH_SOURCE[0]})               <- Display the environment
When this script is called with "sourced mode", i.e. run within current shell,
it will prepare the environment to run other commands, according to OPTIONs,
or clean or display the environment.
  -c, --command=CMD  Specify the command alias to be created for mindriver
  -p, --ps1          Modify PS1 variable for a customized command prompt
  -e, --editor=CMD   Specify the text editor
  -t, --type=EXT     Specify the default text file type
  -f, --file=FILE    Specify the current FILE to be operated by mindriver
  -s, --focus=ALIAS  Specify the current focusing alias
	EOF
}
unvar() { # BKM: clean variables and functions from current shell with unset
	unset mr_sourced dbg arg mr_aliases mr_params ps mr_tps f cmd
	unset -f calrln dbg dv dt err usage_sourced unvar
	unset ERR_ARG ERR_OPT
}
ps='\[\e]0;$($MR_SH ps title)\a\]\[\e[0;92m\]$($MR_SH ps path)'\
'\[\e[0;91m\]$($MR_SH ps focus)\[\e[0;94m\]\w\[\e[0m\]$ '
mr_tps='[),#<>?!/~*]'
if [ "$mr_sourced" = true ]; then
	if [ $# -eq 0 ]; then
		if [ -n "$MR_SH" ]; then
			cmd=$(alias | grep "'$MR_SH'" | sed -e 's/=.*$//' \
				-e 's/^alias //')
			echo "Command alias:"
			alias | grep -E "$MR_SH|'$cmd "
		fi
		[ -n "$MR_PS1" ] && echo 'Command prompt customized.'
		[ -n "$MR_EDITOR" ] && echo "Default editor: $MR_EDITOR"
		[ -n "$MR_TYPE" ] && echo "Default file type: $MR_TYPE"
		[ -n "$MR_FILE" ] && echo "Current file: ${MR_FILE#$PWD/}"
		[ -n "$MR_FOCUS" ] && echo "Current focus: $MR_FOCUS"
		unvar; return  # in sourced mode, return=exit script
		# exit=~ shell, which is usually unexpected
	fi
	for arg do shift; case $arg in --debug) dbg='y';;
		'-?'|-h|--help) usage_sourced; unvar; return;;
		*) set -- "$@" "$arg";;
	esac; done; dargs "$@"
	if [ "$1" = clean ]; then
		if [ -n "$MR_SH" ]; then
			cmd=$(alias | grep "'$MR_SH'" | sed -e 's/=.*$//' \
				-e 's/^alias //')
			mr_aliases=$(alias | grep -E "$MR_SH|'$cmd " \
				| sed -e 's/=.*$//' -e 's/^alias //')
			while IFS= read -r a ; do
				[ -z "$a" ] && continue
				unalias $a; echo "Unalias $a"
			done <<< "$mr_aliases"
		fi
		export -n MR_SH MR_FILE MR_EDITOR MR_TYPE MR_FOCUS
		unset MR_SH MR_FILE MR_EDITOR MR_TYPE MR_FOCUS
		[ -n "$MR_PS1" ] && PS1="$MR_PS1" && unset MR_PS1
		unvar; return
	fi
	mr_params=$(getopt -o c:f:pe:t:s: -l \
		command:,file:,ps,editor:,type:,focus: -n 'mr_src' -- "$@")
	[ $? -ne 0 ] && err "$ERR_ARG" && unvar && return
	eval set -- "$mr_params"
	while : ; do case "$1" in --) shift; break;;
		-c|--command) export MR_SH="$(realpath ${BASH_SOURCE[0]})"
			alias $2="$MR_SH"; echo "Alias $2 was setup."; shift 2;;
		-f|--file) [[ $2 != *.mr ]] && f="$2.mr" || f="$2"
			[ -f "$f" ] && { export MR_FILE="$(realpath $f)"
			export -n MR_FOCUS; echo "Current file: $MR_FILE"; } \
			|| err "$f no exist."; shift 2;;
		-p|--ps) [ -z "$MR_PS1" ] && MR_PS1="$PS1"; PS1="$ps"; shift;;
		-e|--editor) [ -n "$(command -v $2)" ] && export MR_EDITOR="$2"\
			|| { err "No command $2"; return; }; shift 2;;
		-t|--type) export MR_TYPE="$2"; shift 2;;
		-s|--focus) [ -f "$MR_FILE" ] || { err "No $MR_FILE"; return; }
			if [ -z "$2" ]; then export -n MR_FOCUS
			else f=$(grep $'\t''[[:punct:]]*('"$2$mr_tps" "$MR_FILE")
				[ -n "$f" ] && export MR_FOCUS="$2" || err \
					"No $2 in $MR_FILE"
			fi; shift 2;;
		*) err "$ERR_OPT $1"; unvar; return;;
	esac; done; unvar; return
fi
#=== File Path Functions & PS1 ================================================
hpath() { [[ $1 =~ ^$HOME.* ]] && echo "~${1#$HOME}" || echo "$1"; }
spath() { local abs rel #s:short $1=path
	abs=$(hpath $(realpath "$1")); rel=$(realpath --relative-to="$PWD" "$1")
	[ ${#rel} -lt ${#abs} ] && echo "$rel" || echo "$abs"; }
mr_ps() { local p; case "$1" in
	title) [ -f "$MR_FILE" ] && echo $(basename "$MR_FILE") || echo '_mr_';;
	path) [ -f "$MR_FILE" ] && p=$(spath "$MR_FILE") && echo "${p%.mr} ";;
	focus) [ ! -f "$MR_FILE" ] || [ -z "$MR_FOCUS" ] && return
		p="$(grep $'\t''[[:punct:]]*('"$MR_FOCUS$mr_tps" "$MR_FILE")"
		[ -n "$p" ] && echo "$MR_FOCUS "
esac; }
samepath() { [[ $(stat -L -c %d:%i "$1") = $(stat -L -c %d:%i "$2") ]] && echo y; }
#== Assert Functions ===========================================================
assertx() { >&2 echo "ASSERT_FAIL($(caller 1 | cut -d ' ' -f1)): $@"; exit; }
assert() { [ "$@" ] || assertx "$*"; }
assert_match() { [[ "$1" =~ $2 ]] || assertx "$1 =~ $2"; }
#== Radix64 Functions ==========================================================
# integer<->radix64(r64x, an implementation of base64) conversion
# https://unix.stackexchange.com/questions/3478/how-can-i-check-the-base64-value-for-an-integer
int2r64x() { awk -M 'NR==FNR{a[NR-1]=$0;next}{if($0==0){print"A";next}o="";for(n=$0;n!=0;n=int(n/64))o=a[n%64]o;print o}' <(printf %s\\n {A..Z} {a..z} {0..9} - _) - <<< $1; }
r64x2int() { awk -M 'NR==FNR{a[$0]=NR-1;next}{n=0;for(i=1;i<=length($0);i++)n=n*64+a[substr($0,i,1)];print n}' <(printf %s\\n {A..Z} {a..z} {0..9} - _) - <<< $1; }
rand64x() { int2r64x $RANDOM; }
date2r64x() { int2r64x $(date +%s); }
#== String Functions ===========================================================
trim_txt() { local str=$(sed 's/[[:space:]]*$//' <<< "$1")
	sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' <<< "$str"
} # remove trailing spaces of each line & trailing newlines of the text
txt2lc() { echo "$1" | wc -l; }
esc4sed() { local a=$(sed 's/[&/\]/\\&/g; s/\t/\\t/g' <<< "$1")
	echo "${a//$'\n'/'\n'}"
} #escape & / \, change tab & newline, to make a string usable in sed
lns2ln() { [ -z "$1" ] && { [ -n "$2" ] && echo "$2"; return; }
	[ -z "$2" ] && echo "$1" && return
	local l1e=$(echo -n ${1: -1} | wc -c) l2b=$(echo -n ${2:0:1} | wc -c)
	[ $l1e -gt 1 -a $l2b -gt 1 ] && echo "$1$2" || echo "$1 $2"
} # combine 2 lines into 1, no space for wide chars. $1=line1 $2=line2
txt2hl() { dargs "$@"; local hl
	while IFS= read -r ln; do
    		if [ -z "$hl" ]; then hl="$ln"
		elif [[ "$ln" =~ ^\\[[:space:]] ]]; then
			ln=$(sed -e 's/^\\[[:space:]]*//' <<< "$ln")
			hl=$(lns2ln "$hl" "$ln")
		else break; fi
	done <<< "$1"; echo "$hl"
} # hl: head line.
#== Meta & Alias Functions =====================================================
ln2meta() { dargs "$@"; mr_as='' mr_tp='' mr_dr=''
	local RE_DR='^[0-9]{8}(-[0-9]{0,8})?|-$'
	if [[ $1 =~ ^[[:punct:]]*\(([^[:space:]\)]+)\) ]]; then
		local meta=${BASH_REMATCH[1]}
		if [[ $meta =~ ^(.*)([,#><?!/~])(.*)$ ]]; then
			mr_as=${BASH_REMATCH[1]}
			mr_tp=${BASH_REMATCH[2]}
			mr_dr=${BASH_REMATCH[3]}
			[ -n "$mr_dr" ] && assert_match "$mr_dr" "$RE_DR"
		elif [[ $meta =~ $RE_DR ]]; then mr_dr="$meta"
		else mr_as="$meta"
		fi
	fi; dv mr_as mr_tp mr_dr
}; mr_as='' mr_tp='' mr_dr=''
ln2as() { ln2meta "$1"; echo "$mr_as"; }
#== NoteCount(nc) & Index(i) Functions =========================================
f2nc() { local nc=$(sed -n '1s/^\([0-9]*\)\t.*/\1/p' "$1")
	[ -z "$nc" ] && erx "No note count in $1." || echo "$nc"
} # file->note_count
ad2i() { dargs "$@"; local ad="$1" nc
	[ "$ad" = '+' ] && { [ -n "$MR_FOCUS" ] && ad="$MR_FOCUS" || {
		err "Address + without MR_FOCUS defined."; return 5; };}
	[ -n "$3" ] && nc="$3" || { nc=$(f2nc "$2"); [ -z "$nc" ] && {
		err "No note count in $2."; return 6; };}
	if [[ $ad =~ ^[0-9]+$ ]]; then [ "$ad" -gt "$nc" ] && {
		err "Too big index $ad(>$nc)"; return 2; }
	else ad=$(awk -F'\t' \
		'$6 ~ /[[:punct:]]*\('"$ad$mr_tps"'/{print NR-1; exit}' "$2")
		[ -z "$ad" -o "$ad" -gt "$nc" ] && {
			err "Alias $1 not found."; return 4; }
	fi; echo "$ad"
} # $1=ad $2=file [$3=nc] address(integer|alias)->integer
i2flds() { dargs "$@"; assert -n "$2" -a -f "$2"
	local ln=$(sed "$(($1+1))p; d" "$2"); assert -n "$ln"
	IFS=$'\t' read -r -a mr_flds <<< "$ln"
}; declare -a mr_flds # $1=idx $2=file
i2tlrg() { awk -F'\t' -v idx=$1 '
	NR == 1 { from = $1 + 2; to = $1 + $2 + 1 }
	NR > 1 && NR <= idx + 1 { from = to + 1; to = from + $2 - 1 }
	NR > idx + 1 { exit }
	END { if (from == to) print from; else printf("%s,%s", from, to) }
	' "$2"
} # Get text line range $1=idx $2=file
i2txt() { local tlrg=$(i2tlrg "$1" "$2"); sed -n "${tlrg}p" "$2"; }
sig2i() { awk -F'\t' -v ct=$1 -v sig=$2 '
	NR == 1 { nc = $1 }
	NR <= nc + 2 { if ( $3 == ct && $4 == sig ) { print NR - 1; exit }
	}' "$3"
} # $1=ct $2=sig $3=file
i2top() { awk -F'\t' -v idx="$1" 'BEGIN { top = idx }
	NR == 1 { nc = $1 }
	NR == idx + 1 { lvl = $1 }
	NR > idx + 1 && NR <= nc + 1 { if ($1 > lvl) top = NR - 1; else exit }
	END { print top }' "$2"
} # $1=idx $2=file
irg2tlrg() { awk -F'\t' -v from="$1" -v to="$2" '
	NR == 1 { tf = $1 + 2; tt = $1 + $2 + 1 }
	NR > 1 && NR <= from + 1 { tf = tt + 1; tt = tf + $2 - 1 }
	NR > from + 1 && NR <= to + 1 { tt = tt + $2 }
	NR > to + 1 { exit }
	END { if (tf == tt) print tf; else printf("%s,%s", tf, tt) }' "$3"
} # $1=from $2=to $3=file
#== Lock Functions =============================================================
dest2lock() { dargs "$@"; assert -f "$1"
	local fn=$(basename "$1") dir=$(realpath "$1"); dir=$(dirname "dir")
	fn="$dir/...$fn...$2..."
	case $2 in
		f) fn="$fn$(rand64x)...$MR_TYPE" ;;
		a|i|b|op) fn="$fn$3...$4...$(rand64x)...$MR_TYPE" ;;
		o|os) local as="$5"
			if [ -z "$as" ]; then as="$MR_TYPE"
			elif [[ $as != *.* ]]; then as="$as...$MR_TYPE"; fi
			fn="$fn$3...$4...$as";;
	esac; dv fn; echo "$fn"
} # $1=file $2=dop $3=ct $4=sig $5=alias
#== Tree Functions =============================================================
declare -a mr_roots mr_tops
i_in_trees() { local tail=$((${#mr_roots[@]}-1)); dv tail
	for idx in $(seq 0 $tail); do
		[ $1 -ge ${mr_roots[$idx]} -a $1 -le ${mr_tops[$idx]} ] && {
			dbg "$1's in (${mr_roots[$idx]}, ${mr_tops[$idx]})"
			return 1; }
	done; return 0
} # $1=i, return: 0:not in, 1:in
i2trees() { i_in_trees $1; [ $? -ne 0 ] && return 0
	local top=$(i2top $1 "$2"); assert -n "$top"; dv top
	local tail=$((${#mr_roots[@]}-1)); dv tail
	for idx in $(seq $tail -1 0); do
		[ ${mr_roots[$idx]} -ge $1 -a ${mr_tops[$idx]} -le $top ] && {
			dbg "Remove range[$idx]:" \
			"(${mr_roots[$idx]}, ${mr_tops[$idx]})"
			unset mr_roots[$idx] mr_tops[$idx]; }
	done
	mr_roots+=("$1"); mr_tops+=("$top")
	dbg "($1, $top) is added."; return 0
} # $1=i $2=file
iter_adws() { dargs "$@"; assert -n "$1" -a -n "$2" -a -f "$2" -a -n "$4"
	local adws="$1" file="$2" nc="$3" func="$4" w i fr to; shift 4
       	[ -z "$nc" ] && lc=$(f2nc "$file")
	for w in $adws; do
		if [[ "$w" =~ ^[^,]+,[^,]+$ ]]; then
			fr=$(ad2i $(sed 's/,.*$//' <<< "$w") "$file" $nc)
			to=$(ad2i $(sed 's/^.*,//' <<< "$w") "$file" $nc)
		else fr=$(ad2i "$w" "$file" "$nc"); to=$fr
		fi; [ -z "$fr" -o -z "$to" ] && err "Wrong adw $w." && return 1
		for i in $(seq $fr $to); do
			$func $i "$file" $nc "$@"; [ $? -ne 0 ] && {
				err "$func($i, $file, $nc, $*)"; return 1; }
		done
	done; return 0
} # $1=adws $2=file $3=nc $4=func(i, file, nc, context...) $5+=context
adws2trees() {
	iter_adws "$1" "$2" '' i2trees; return $?
} # $1=adws $2=file
iter_trees() { local last=$((${#mr_roots[@]}-1)) func="$1"; shift
	for idx in $(seq 0 $last); do
		$func ${mr_roots[$idx]} ${mr_tops[$idx]} "$@"; [ $? -ne 0 ] && {
			err "$func(${mr_roots[$idx]}, ${mr_tops[$idx]}, $*)"
			return 1; }
	done
} # $1=func(from, to, context...) $2+=context
list_tree() {
	awk -F'\t' -v fr=$1 -v to=$2 '
	NR == 1 { nc = $1 }
	NR > fr && NR <= to + 1 { printf "%s %s %s\n", NR -1, $1, $6 }
	' "$3"
} # $1=from $2=to $3=file
list_trees() { iter_trees list_tree "$1"; } # $1=file
ls1leaf() { dargs "$@"
} # $1=id $2=file $3=level $4=relpath
trees2seds() { dargs "$@"; local last=$((${#mr_roots[@]}-1)) ised tsed nc=0
	for idx in $(seq 0 $last); do
		local fr=${mr_roots[$idx]} to=${mr_tops[$idx]} irg
		nc=$((nc+to-fr+1))
		[ "$fr" = "$to" ] && irg="$((fr+1))" \
			|| irg="$((fr+1)),$((to+1))"
		ised="$ised$irg;"
		local trg=$(irg2tlrg "$fr" "$to" "$1")
		tsed="$tsed$trg;"
		local rtlv='' ln lv dlv="$2" lvsed sigsed
		for j in $(seq $fr $to); do
			ln=$(sed -n "$((j+1))p" "$1")
			lv=${ln%%$'\t'*}
			[ -z "$rtlv" ] && rtlv="$lv"
			lv=$((lv+dlv-rtlv))
			lvsed="$lvsed$((j+1))s/^[0-9]*/$lv/;"
		done
	done; dv ised tsed nc lvsed
	echo "$ised" "$tsed" "$nc" "$lvsed"
} # trees->iln_sed & txt_sed & tree_nc. $1=file $2=dlv
#== HELPER FUNCTIONS ===========================================================
mr_init() { dargs "$@";	assert ! -f "$1"
	local bs=$(basename "$1") dt=$(date2r64x)
	echo -n 0$'\t'1$'\t'$dt$'\t'$(rand64x)$'\t'$dt$'\n'"What's in $bs?" \
		> "$1"; return 0
} # init a new mr file, $1=path
edit_txt() {
	local edr="$2"; [ -z "$edr" ] && edr="$MR_EDITOR"
	[ -z "$edr" -a -n "$(command -v vim)" ] && edr='vim'
	[ -z "$edr" -a -n "$(command -v vi)" ] && edr='vi'
	[ -z "$edr" -a -n "$(command -v nano)" ] && edr='nano'
	[ -z "$edr" ] && err "No editor specified." && return 1
	[ -z "$(command -v $edr)" ] && err "No $edr command." && return 2
        [ -f "$3" ] && err "Another process is editing $3." && return 3
	[ -n "$1" ] && echo "$1" > "$3" || touch "$3"
	$edr "$3"
} # $1=text $2=editor $3=temp_file
resign_ilnbuf() { dargs "$@"; local ln; while IFS= read -r ln; do sed \
	"s/^\(\([^[:space:]]\+\t\)\{3\}\)[^[:space:]]\+/\1$(rand64x)/" <<< "$ln"
done <<< "$1"; } # $1=ilnbuf
#== Core Processor for move/copy/remove/add/update =============================
usage_cpu() { cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) cpu [ARGS]
ARGS    \$1    \$2   \$3    \$4         \$5    \$6  Remark
add     n[e]  txt  edtr  i|a|b|f    dest  ad  \$1:n:note \$4:i:into
update  n[e]  txt  edtr  o[p|s]     dest  ad     e:edit    o:off|replace s:sed
copy    ac    src  adws  i|a|b|o|f  dest  ad     a:adws    b:before   p:append
move    acr   src  adws  i|a|b|o|f  dest  ad     c:copy    a:after
remove  ar    src  adws  -          -     -      r:remove  f:new|EOF
	EOF
}
cpu() { dargs "$@"; local sf="$MR_FILE" df="$MR_FILE" di dlv=0
	# Check $1-4
	if [[ "$1" =~ ^(ar|acr|ac)$ ]]; then
		[ -n "$2" ] && sf="$2"
		[ -z "$sf" ] && { err "Source file not specified."; return 2; }
		[[ "$sf" != *.mr ]] && sf="$sf.mr"
		[ ! -f "$sf" ] && { err "$sf is not a file."; return 3; }
		[ -z "$3" ] && { err "Empty \$3."; return 4; }
		adws2trees "$3" "$sf"
		[ $? -ne 0 ] && { err "adws2trees."; return 5; }
		i_in_trees 0; [ $? -ne 0 ] && { err \
			"Don't move|copy|remove note 0."; return 6; }
		[[ "$1" = ac* && ! "$4" =~ ^(i|a|b|o|f)$ ]] && {
			err "Wrong \$4:$4."; return 7; }
	elif [[ "$1" =~ ^(n|ne)$ ]]; then
		[[ ! "$4" =~ ^(i|a|b|o|op|os|f)$ ]] && {
			err "Wrong \$4:$4."; return 7; }
	else err "Unsupported \$1:$1."; return 1; fi
	# Check $5-6
	if [[ "$1" =~ ^(ac|acr|n|ne)$ ]]; then
		[ -n "$5" ] && df="$5"
		[ -z "$df" ] && { err "Target file not specified."; return 2; }
		[[ "$df" != *.mr ]] && df="$df.mr"
		if [[ ${4:0:1} =~ ^(b|a|i|o)$ ]]; then
			[ ! -f "$df" ] && { err "$df's not a file."; return 3; }
			di=$(ad2i "$6" "$df"); [ $? -ne 0 -o -z "$di" ] && {
				err "$6's a wrong address."; return 7; }
			[[ $di = 0 && ! ($1 = n* && $4 = o*) ]] && {
				err "Don't target note 0."; return 6; }
			i2flds "$di" "$df"; dflds=("${mr_flds[@]}")
			[[ $4 = i ]] && dlv=$((dflds[0]+1)) || dlv=${dflds[0]}
			if [[ "$1" = a* && -n $(samepath "$sf" "$df") ]]; then
				i_in_trees $di; [ $? -ne 0 ] && { err \
				"Can't copy notes to their child."; return 8; }
			fi
		elif [[ "$1" = n* && ! -f "$df" ]]; then # n+f(new)
			read -p "$df doesn't exist, create it?(y/n) " -n 1 -r
			[[ $REPLY =~ ^[Yy]$ ]] && echo || { echo; return 9; }
		fi
	fi
	# Ask for confirmation
	if [[ "$1" =~ ^(ac|ar|acr)$ ]]; then
		local act='' fr=$(spath "$sf")
		case $1 in ac) act='copy';; acr) act='move';; ar) act='remove';;
		esac; echo "You'll actually $act these notes from $fr..."
		list_trees "$sf"
		if [[ "$1" = ac* ]]; then
			local to=$(spath "$df") flw='the following note of'
			case "$4" in
				i) echo "...into $flw $to:"
					ls1leaf "$di" "$df" 0;;
				a) echo "...to after $flw $to:"
					ls1leaf "$di" "$df" 0;;
				b) echo "...to before $flw $to:"
					ls1leaf "$di" "$df" 0;;
				o) echo "...to replace $flw $to:"
					ls1leaf "$di" "$df" -1;;
				f) [ -f "$df" ] && echo "...to the end of $to."\
					|| echo "...to a nonexistent file $to,"\
					"so it will be created.";;
			esac
		fi
		read -p "Continue?(y/n) " -n 1 -r
		[[ $REPLY =~ ^[Yy]$ ]] && echo || { echo; return 9; }
		local seds=($(trees2seds "$sf" "$dlv"))
		if [[ $1 = ac* ]]; then
			ilnbuf=$(sed -n "${seds[3]}${seds[0]//;/p;}" "$sf")
			[[ $1 = ac ]] && ilnbuf=$(resign_ilnbuf "$ilnbuf")
			txtbuf=$(sed -n "${seds[1]//;/p;}" "$sf")
		fi
		if [[ $1 = *r* ]]; then
			local rmsed="${seds[0]}${seds[1]}"
			sed -i ${rmsed//;/d;} "$sf"
			local snc=$(f2nc "$sf") nc=${seds[2]}
			sed -i "1s/^[0-9]\+/$((snc-nc))/" "$sf"
			[[ $1 = ar ]] && return 0
		fi
	else # $1=n[e]
		txtbuf=$(trim_txt "$2")
		if [[ $4 = o || $4 = os ]]; then
			local dtxt=$(i2txt "$di" "$5")
			if [[ $4 = os ]]; then
				[ -z "$txtbuf" ] && txtbuf="$dtxt" || \
					txtbuf=$(sed -e "$txtbuf" <<< "$dtxt")
				[ $? -ne 0 ] && return 3
			fi
		fi
		if [ $1 = ne ]; then
			local tmpf=$(dest2lock "$df" "$4" "${dflds[2]}" \
				"${dflds[3]}" $(ln2as "${dflds[6]}"))
			edit_txt "$txtbuf" "$3" "$tmpf"
			[ ! -f "$tmpf" ] && return 4
			txtbuf=$(cat "$tmpf"); rm -f "$tmpf"
			txtbuf=$(trim_txt "$txtbuf")
		fi
		if [[ $4 = o || $4 = os ]]; then
			[[ "$txtbuf" == "$dtxt" ]] && {
				dbg "Nothing changed. Exit."; return 0; }
		fi
		local dt=$(date2r64x) lc=$(txt2lc "$txtbuf")
		local hl=$(txt2hl "$txtbuf")
		ilnbuf=$'\t'$dt$'\t'"$hl"
		if [ ${4:0:1} = o ]; then
			[ $4 = op ] && lc=$((${dflds[1]}+$(txt2lc "$txtbuf")))
			ilnbuf=$dlv$'\t'$lc$'\t'${dflds[2]}$'\t'"${dflds[3]}$ilnbuf"
		else #a,b,i,f
			ilnbuf=$dlv$'\t'$lc$'\t'$dt$'\t'"$(rand64x)$ilnbuf"
		fi
	fi; dt ilnbuf txtbuf
	# Use saved ct+sig to get the di back
	if [[ ${4:0:1} =~ ^(b|a|i|o)$ ]]; then
		local ndi=$(sig2i ${dflds[2]} ${dflds[3]} $df); dv ndi
		if [ -z "$ndi" ]; then
			err "Target lost!"
			# ask user to input a new target here
		else [ "$ndi" -ne "$di" ] && dbg "Note $di->$ndi."; fi
		di="$ndi"
	elif [ ! -f "$df" ]; then mr_init "$df"
	fi
	local dnc=$(f2nc "$df") ilnc=$(txt2lc "$ilnbuf") tlrg dtop dsed
	ilnbuf=$(esc4sed "$ilnbuf"); txtbuf=$(esc4sed "$txtbuf")
	case "${4:0:1}" in
		o) if [[ $1 = n* ]]; then
			tlrg=$(i2tlrg "$di" "$df")
			if [[ $4 = op ]];
				dsed=${tlrg#*,}"a $txtbuf"
			then # $4=o|os
				dsed="${tlrg}c $txtbuf"
			fi
			dsed="$dsed"$'\n'"$((di+1))c $ilnbuf"
		   else # $1=a*
			   dtop=$(i2top "$di" "$df")
			   tlrg=$(irg2tlrg "$di" "$dtop" "$df")
			   dsed="${tlrg}c $txtbuf"$'\n'
			   dsed="$dsed$((di+1)),$((dtop+1))c $ilnbuf"$'\n'
			   dsed="$dsed""1s/^[0-9]\+/$((dnc+ilnc+di-dtop-1))/"
		   fi;;
		b) tlrg=$(i2tlrg "$di" "$df")
			dsed=${tlrg%,*}"i $txtbuf"$'\n'$((di+1))"i $ilnbuf"
			dsed="$dsed"$'\n'"1s/^[0-9]\+/$((dnc+ilnc))/";;
		a|i) dtop=$(i2top "$di" "$df"); tlrg=$(i2tlrg "$dtop" "$df")
			dsed=${tlrg#*,}"a $txtbuf"$'\n'$((dtop+1))"a $ilnbuf"
			dsed="$dsed"$'\n'"1s/^[0-9]\+/$((dnc+ilnc))/";;
		f) dsed=$((dnc+1))"a $ilnbuf"$'\n'"\$a $txtbuf"
			dsed="$dsed"$'\n'"1s/^[0-9]\+/$((dnc+ilnc))/";;
		*) err "Wrong \$4:$4."; return 7;;
	esac; dt dsed
	[ -n "$dsed" ] && sed -i -e "$dsed" "$5"
	return 0
}
#=== ADD a new note ============================================================
usage_add() { cat<<-EOF
Usage: $(basename ${BASH_SOURCE[0]}) add [OPTION]... [MESSAGE]
Add a new note to a specified FILE at specified POSITION with specified MESSAGE.
  -f, --file=<path>     Specify the FILE to which the note will be added.
                        If not specified, use MR_FILE.
  -m, --message=<text>  Specify the MESSAGE of the note.
  -e, --edit[=cmd]      Call an EDITOR to edit the MESSAGE of the note.
                        If no EDITOR specified, use MR_EDITOR, vim, vi or nano.
  -i, --into=<adr>      Specify the note under which the new one will be added.
  -a, --after=<adr>	Specify the note after which the new one will be added.
  -b, --before=<adr>    Specify the note before which the new one will be added.
                        Only 1 of i(nto)|a(fter)|b(fore) is allowed.
	EOF
}
mr_add() { PARAMS=$(getopt -o f:m:e::i:a:b: -l \
	file:,message:,edit::,into:,after:,before: \
	-n 'mr_add' -- "$@"); [ $? -ne 0 ] && err "$ERR_ARG" && return
	eval set -- "$PARAMS"; dargs "$@"
	local f="$MR_FILE" msg='' e='' edr='' x='' xa=''
	local err_multi="Only 1 of i(nto)|a(fter)|b(efore) allowed."
	while : ; do case "$1" in --) shift; break;;
		-f|--file) f="$2"; shift 2;;
		-m|--message) msg="$2"; shift 2;;
		-e|--edit) e=e; edr="$2"; shift 2;;
		-i|--into) [ -n "$x" ] && { err "$err_multi"; return; }
			x=i; xa="$2"; shift 2;;
		-a|--after) [ -n "$x" ] && { err "$err_multi"; return; }
			x=a; xa="$2"; shift 2;;
		-b|--before) [ -n "$x" ] && { err "$err_multi"; return; }
			x=b; xa="$2"; shift 2;;
		*) err "$ERR_OPT $1"; return;;
	esac; done
	[ -z "$msg" ] && msg="$*"; [ -z "$x" ] && x=f
	cpu n$e "$msg" "$edr" $x "$f" "$xa"
}
#=== MAIN ======================================================================
usage() { cat<<-EOF
mindriver, in which logs float down to the human world.
Usage:
  . $(basename ${BASH_SOURCE[0]}) [OPTION]...                  <-'Sourced Mode'
  $(basename ${BASH_SOURCE[0]}) <COMMAND> [OPTION]...
"Sourced Mode" is used to set or clean runtime environment, you can run
". $(basename ${BASH_SOURCE[0]}) --help" to get its usage information.
The commands are:
  help    Show this document.
  add     Create a new note.
  rm      Remove one or more notes.
  cat     View the content of one or more notes.
  update  Update the content of one or more notes.
  mv      Move one or more notes to another file or position.
  ls      List the notes under one or more parent notes.
  grep    Search pattern in each note or file.
You can run 'mr <command> <-h|--help|-?>' to get the document of each command.
	EOF
}; hlp=''
for arg do shift; case $arg in
	'-?'|-h|--help) hlp='y';;
	--debug) dbg='y';;
	*) set -- "$@" "$arg";;
esac; done; dargs "$@"
[ $# -eq 0 ] && usage && exit 0  #No arg, show usage
case "$1" in help) usage;;
	ps) shift; mr_ps "$@";;
	cpu) shift; [ -n "$hlp" ] && usage_cpu || cpu "$@";;
	cat) shift; [ -n "$hlp" ] && usage_cat || mr_cat "$@";;
	upd) shift; [ -n "$hlp" ] && usage_upd || mr_upd "$@";;
	add) shift; [ -n "$hlp" ] && usage_add || mr_add "$@";;
	rm) shift; [ -n "$hlp" ] && usage_rm || mr_rm "$@";;
	mv) shift; [ -n "$hlp" ] && usage_mv || mr_mv "$@";;
	ls) shift; [ -n "$hlp" ] && usage_ls || mr_ls "$@";;
	grep) shift; [ -n "$hlp" ] && usage_grep || mr_grep "$@";;
	*) dir=$(dirname ${BASH_SOURCE[0]}) cmd=$1; shift
		if [ -f "$dir/mr.$cmd.sh" ]; then . "$dir/mr.$cmd.sh" "$@"
		else err "Incorrect command: $cmd"; usage; fi;;
esac
