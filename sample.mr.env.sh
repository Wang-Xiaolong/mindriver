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
alias ${c}cp="$c cp"
alias ${c}l="$c ls"
alias ${c}lt="$c ls -t"
alias ${c}lf="$c ls -f"
alias ${c}l0="$c ls -l0 -f"
alias ${c}l+="$c ls +"
alias ${c}lt+="$c ls -t +"
unset c dir
