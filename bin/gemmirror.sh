#!/usr/bin/env bash
set -e # abort on error

# load rvm ruby
source ~/.rvm/environments/ruby-1.9.3-p448@rubygems-mirror-command

cd ~/code/misc/rubygems-mirror-command

until rubygems-mirror-command fetch true; do
    echo "gem mirror crashed with exit code $?.  Respawning.." >&2
    sleep 1
done
