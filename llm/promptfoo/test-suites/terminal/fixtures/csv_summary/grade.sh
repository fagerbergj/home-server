n=$(tr -dc '0-9' < summary.txt 2>/dev/null)
[ "$n" = "3" ]
