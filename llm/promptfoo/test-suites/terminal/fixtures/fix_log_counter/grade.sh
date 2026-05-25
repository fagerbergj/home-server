n=$(bash count.sh 2>&1 | tr -dc '0-9')
[ "$n" = "5" ]
