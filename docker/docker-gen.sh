pName="container_env_service"
templatepath="docker-compose.tmpl.yml"
template_content=$(cat "$templatepath")

runinput='echo "'$template_content'" | envsubst'

docker-compose -f ./docker-compose.env-builder.yml -p $pName up
result=$(docker-compose -f ./docker-compose.env-builder.yml run test /bin/sh -c "$runinput")
docker-compose -f ./docker-compose.env-builder.yml -p $pName down

echo "$result"

tmpfile="mktemp.yml"
cat <<< "$result" > $tmpfile
sed -i 's/\r//g' $tmpfile

echo "$(cat $tmpfile)"

sName="container_core_service"
docker-compose -f $tmpfile -p $sName up

#do testing and stuff

docker-compose -f $tmpfile -p $sName down
docker-compose -f $tmpfile -p $sName rm

rm $tmpfile