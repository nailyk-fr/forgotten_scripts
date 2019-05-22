#!/bin/bash


###
### Script used to crawl faved toots on mastodon
### and retrieve all the *youtube* URLs into. 
###
###  Take number of toot to crawl as argument
###      ./masto_play-later.sh 150 to crawl 150
###      will crawl 160 toots (each query return
###      40 toots by design)
###
###  Will produce a 'to_download' test file
###      containing 1 youtube URL per line
###
###  After authenticating, two file needs to be
###      keep: `.token` & `.client_id`. Those files
###      store the necessary identifiers to get
###      the script working. 

F_TMP=$(mktemp)
F_TMP_URL=$(mktemp)

create_id() {
	echo -n "Instance uri: "
	read A_INSTANCE

	curl --header "Content-Type: application/json" \
	--request POST \
	--data '{"client_name":"play_later","redirect_uris":"urn:ietf:wg:oauth:2.0:oob","scopes":"read"}' \
	  ${A_INSTANCE}/api/v1/apps > ${F_TMP}

	V_NAME=$(jq .name ${F_TMP})
	V_CLIENTID=$(jq .client_id ${F_TMP})
	V_CLIENTSECRET=$(jq .client_secret ${F_TMP})
	V_CLIENTVAPID=$(jq .vapid_key ${F_TMP})
	V_INSTANCEURI=${A_INSTANCE}


# the sed trick is to get rid of doubles quotes on each var
	cat >> .client_id << EOF
V_NAME=$(sed -e 's/^"//' -e 's/"$//' <<<"${V_NAME}")
V_CLIENTID=$(sed -e 's/^"//' -e 's/"$//' <<<"${V_CLIENTID}")
V_CLIENTSECRET=$(sed -e 's/^"//' -e 's/"$//' <<<"${V_CLIENTSECRET}")
V_CLIENTVAPID=$(sed -e 's/^"//' -e 's/"$//' <<<"${V_CLIENTVAPID}")
V_INSTANCEURI=$(sed -e 's/^"//' -e 's/"$//' <<<"${V_INSTANCEURI}")
EOF

	# reload the var to get rid of double quotes : 
	load_id

}

load_id() {
	. .client_id
}

create_token() {

	echo "Please go to ${V_INSTANCEURI}/oauth/authorize?scope=read&response_type=code&redirect_uri=urn:ietf:wg:oauth:2.0:oob&client_id=${V_CLIENTID}"

	echo -n "Paste returned token: "
	read -s A_PASSWD

	echo "${A_PASSWD}" > .token

	curl -X POST -d "client_id=${V_CLIENTID}&client_secret=${V_CLIENTSECRET}&grant_type=authorization_code&code=$(cat .token)&redirect_uri=urn:ietf:wg:oauth:2.0:oob" -Ss ${V_INSTANCEURI}/oauth/token > .token

	# now load the token
	load_token

}

load_token() {
	V_TOKEN=$(jq .access_token .token | sed -e 's/^"//' -e 's/"$//')

	if [[ $? -eq 0 ]]
	then
		echo "Authentication succesfull"
	else
		echo "Error while enrolling $0"
	fi

}

remove_temp() {
	if [[ -f ${F_TMP} ]]
	then
		rm ${F_TMP}
	fi

	if [[ -f ${F_TMP_URL} ]]
	then
		rm ${F_TMP_URL}
	fi
}

check_auth() {

	echo -n " - Checking if everything went fine. Authenticated as: "
	curl --header "Authorization: Bearer ${V_TOKEN}" -sS ${V_INSTANCEURI}/api/v1/accounts/verify_credentials | jq -e .username

	if [[ $? -ne 0 ]]
	then
		echo "Something went wrong :("
		exit 2
	fi

}

toot_crawler() {

		# Get faved toot content
		if [[ ! ${V_NEXT:-} ]]
		then
			curl -i --header "Authorization: Bearer ${V_TOKEN}" -sS ${V_INSTANCEURI}/api/v1/favourites?limit=40 > ${F_TMP}
		else
			curl -i --header "Authorization: Bearer ${V_TOKEN}" -sS ${V_NEXT} > ${F_TMP}
		fi

		# Store youtube urls
		tail -1 ${F_TMP}  | jq '.[] |  .content' | grep -i youtube | egrep -o 'https?://[^ ]+' | sed -e 's!\\"!!' | grep youtube >> ${F_TMP_URL}

		# get next URL from 'Link header'
		V_NEXT=$(cat ${F_TMP} | grep -e "^link:" | egrep -o 'https?://[^ ]+' | grep max_id | sed -e 's,>;,,' )

		V_CRAWLED=$((${V_CRAWLED} + 40))
}


if [[ ! -f .client_id ]]
then
	create_id
else
	load_id
fi

echo "Now running ${V_NAME} with client ID ${V_CLIENTID} on ${V_INSTANCEURI}"

# if token does not exist, create one : 
if [[ ! -f .token ]]
then
	create_token
else
	load_token
fi

check_auth

if [[ ${1:-} ]]
then
	A_CRAWL_TOOTS=${1}
else
	A_CRAWL_TOOTS=40
fi

echo "Gonna look into the ${A_CRAWL_TOOTS} faved toots"

V_CRAWLED=0
while [ ${V_CRAWLED} -lt ${A_CRAWL_TOOTS} ]
do
	toot_crawler
done

cp ${F_TMP_URL} to_download

