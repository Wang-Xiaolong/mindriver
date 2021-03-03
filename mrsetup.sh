#!/usr/bin/env bash
[[ $_ == $0 ]] && echo "Only run in sourced mode." && exit
dir=$(dirname $(realpath ${BASH_SOURCE[0]}))
[ ! -f "$dir/mr.sh" ] && echo "mr.sh not found." && unset dir && return
[ -n "$1" ] && . "$dir/mr.sh" -c mr -f "$1" -p || . "$dir/mr.sh" -c mr -p
unset dir
alias mr0=". $MR_SH"
alias mrf=". $MR_SH -f"
alias mrclean=". $MR_SH clean"
alias mrinit="$MR_SH init"
alias mra="$MR_SH a"
alias mra0="$MR_SH a -f 0"
alias mras="$MR_SH as"
alias mrv="$MR_SH v"
alias mre="$MR_SH e"
alias mred="$MR_SH e -d"
alias mrm="$MR_SH m"
alias mrl="$MR_SH l"
alias mrlv="$MR_SH l -v"
alias mrls="$MR_SH ls"
