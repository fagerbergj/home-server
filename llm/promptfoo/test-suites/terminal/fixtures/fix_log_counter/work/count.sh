#!/usr/bin/env bash
count=0
for f in *.log; do
  count=$(wc -l $f)
done
echo $count
