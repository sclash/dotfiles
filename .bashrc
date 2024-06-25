#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

setxkbmap -layout it
exec zsh
#systemctl start iwd
alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '




[[ -f ~/.bashrc ]] && . ~/.bashrc
export PATH=~/bin:$PATH
