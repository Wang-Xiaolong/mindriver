#!/usr/bin/env bash
[[ $_ == $0 ]] && echo "Only run in sourced mode." && exit
mr_dir=$(dirname $(realpath ${BASH_SOURCE[0]}))
[ ! -f "$mr_dir/mr.sh" ] && echo "mr.sh not found." && return
[ -n "$1" ] && mr_file="$1" || mr_file="$mr_dir/log/wxl.mr"
. "$mr_dir/mr.sh" -c mr -e mr -t marktree -f "$mr_file"
alias mrf=". $MR_SH -f"
alias mrclean=". $MR_SH clean"
alias mra="$MR_SH a"
alias mre="$MR_SH e"
alias mrm="$MR_SH m"
alias mrl="$MR_SH l"
alias mrlv="$MR_SH l -v"
alias mrls="$MR_SH ls"
unset mr_dir mr_file
