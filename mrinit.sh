#!/usr/bin/env bash
[[ $_ == $0 ]] && echo "Only run in sourced mode." && exit
mr_dir=$(dirname $(realpath ${BASH_SOURCE[0]}))
[ ! -f "$mr_dir/mr.sh" ] && echo "mr.sh not found." && return
[ -n "$1" ] && mr_id="$1"
. "$mr_dir/mr.sh" -c mr -i "$mr_id"
alias mri=". $MR_SH -i"
alias mrclean=". $MR_SH clean"
alias mra="$MR_SH a"
alias mre="$MR_SH e"
alias mrm="$MR_SH m"
alias mrl="$MR_SH l"
alias mrlv="$MR_SH l -v"
alias mrls="$MR_SH ls"
unset mr_dir mr_id
