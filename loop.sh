#!/bin/sh

num_loops=3
sleep_time=10

for i in `seq $num_loops`
do
    printf 'Iteration %s\n' $i
    perl linkCheck.pl;
    if [ "$i" -lt "$num_loops" ]; then
        sleep $sleep_time
    fi
done
