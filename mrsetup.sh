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
alias mra="$MR_SH add"
alias mra0="$MR_SH add -f 0"
alias mras="$MR_SH alias"
alias mrc="$MR_SH cat"
alias mre="$MR_SH edit"
alias mred="$MR_SH edit -d"
alias mrm="$MR_SH remove"
alias mrv="$MR_SH move"
alias mrl="$MR_SH log"
alias mrlv="$MR_SH log -v"
alias mrls="$MR_SH ls"
alias mrgf="$MR_SH ls -R | grep -i"
