#!/usr/bin/env bash
[[ $_ == $0 ]] && echo "Only run in sourced mode." && exit
c=mr dir=$(dirname $(realpath ${BASH_SOURCE[0]}))
[ ! -f "$dir/mr.sh" ] && echo "mr.sh not found." && unset c dir && return
. "$dir/mr.sh" -c $c -p -t marktree
alias ${c}.=". $MR_SH"
alias ${c}f=". $MR_SH -f"
alias ${c}+=". $MR_SH -s"
alias ${c}-=". $MR_SH -s ''"
alias ${c}clean=". $MR_SH clean"
alias ${c}p="$c print"
alias ${c}p+="$c print +"
alias ${c}e="$c edit"
alias ${c}a="$c add"
alias ${c}a+="$c add -i+"
alias ${c}m="$c rm"
alias ${c}v="$c mv"
alias ${c}cp="$c mv -c"
alias ${c}l="$c ls"
alias ${c}lt="$c ls -l ''"
alias ${c}lf="$c ls -f"
alias ${c}l+="$c ls +"
alias ${c}lt+="$c ls -l '' +"
alias ${c}s="$c search"
alias ${c}t="$c todo"
unset c dir
