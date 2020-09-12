#!/usr/bin/env bash
[[ $_ == $0 ]] && echo "Only run in sourced mode." && exit
dir=$(dirname $(realpath ${BASH_SOURCE[0]}))
[ ! -f "$dir/mr.sh" ] && echo "mr.sh not found." && unset dir && return
[ -n "$1" ] && file="$1" || file=0
. "$dir/mr.sh" -c mr -f "$file"; unset dir file
alias mrf=". $MR_SH -f"
alias mrclean=". $MR_SH clean"
alias mra="$MR_SH a"
alias mre="$MR_SH e"
alias mrm="$MR_SH m"
alias mrl="$MR_SH l"
alias mrlv="$MR_SH l -v"
alias mrls="$MR_SH ls"
