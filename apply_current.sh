#!/bin/bash

[[ `whoami` == 'root' ]] || eval 'echo "Not root" && exit 1'

for file in $(find . -maxdepth 1 -type f)
do
    cp -vf $file /etc/varnish/${file}
done

service varnish restart
