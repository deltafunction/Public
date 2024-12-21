#!/bin/bash

# Get LastFM recommendations
# Copyright, Frederik Orellana, 2017
# E.g.
# ./get_tracks.sh -t 50 -i mylastfmid --algorithm Similar --loved --popular --library

set -o errexit -o noclobber -o nounset -o pipefail

#SCRIPTPATH=$( cd $(dirname $0) ; pwd -P )
SCRIPTPATH=`dirname $(readlink -f ${0})`

usage() { echo "Usage: $0 [--username <string>][--tracks <int>][--algorithm <string>] [--loved][--popular][--library]" 1>&2; exit 1; }

args="$(getopt -o "u:t:a:l:p:m:"  -l "username:,tracks:,algorithm:,loved:,popular:,library:,help" -- "$@")"
eval set -- "$args"

if [ $? -ne 0 ]; then
	usage
fi

# Defaults
username=""
tracks="20"
algorithm="Similar"
loved="1"
popular="0"
library="1"

sampleTracks="yes"
tracksOut=30
tmpPage="/tmp/page.html"

urldecode() {
	sed "s@+@ @g;s@%@\\\\x@g" | xargs -0 printf "%b"
}

urlencode() {
  local LANG=C; local c; while IFS= read -r c; do
    case $c in [a-zA-Z0-9.~_-]) printf "$c"; continue ;; esac
    #c=`echo -n $c | tr '%' '%%'`
    printf "$c" | od -An -tx1 | tr ' ' % | tr -d '\n'
  done <<EOF
$(fold -w1)
EOF
}

# Spotify application client id and secret, from
# https://developer.spotify.com/my-applications/

client_token=`echo -ne $CLIENT_ID:$SECRET | base64 -w 0`
spotify_token=`curl -H "Authorization: Basic $client_token" -d "grant_type=client_credentials" "https://accounts.spotify.com/api/token" | jq -r .access_token`

while [ $# -ge 1 ]; do
	case "$1" in
                -u|--username)
                        username="$2"
                        shift 2
                        ;;
                -t|--tracks)
                        tracks="$2"
                        shift 2
                        ;;
                -a|--algorithm)
                        algorithm="$2"
                        shift 2
                        ;;
                -l|--loved)
                        loved="$2"
                        shift 2
                        ;;
                -p|--popular)
                        popular="$2"
                        shift 2
                        ;;
                -m|--library)
                        library="$2"
                        shift 2
                        ;;
                -h|--help)
                        usage
                        exit 0
                        ;;
                --)
			# No more options left.
			shift
			break
			;;
		*)
			echo "Not implemented: $1" >&2
			exit 1
			;;
       esac
done

if [ -z "$username" ]; then
	usage
	exit 1
fi

ls $tmpPage >& /dev/null && rm $tmpPage

QT_QPA_PLATFORM=offscreen phantomjs $SCRIPTPATH/get_page.js $username $tracks $algorithm $loved $popular $library | \
grep -v 'LOG: ' > $tmpPage

tracksQuotient=1
tracksNum=`cat $tmpPage | sed 's|<tr|\n<tr|g' | grep -E '^<tr ' | wc -l`
if [ $tracksNum -gt $tracksOut ]; then
	tracksRemainder=$(( tracksNum % tracksOut ))
	tracksQuotient=$(( (tracksNum-tracksRemainder) / tracksOut ))
fi

i=0
echo -n "["
[ ! -s $tmpPage ] || cat $tmpPage | sed 's|<tr|\n<tr|g' | grep -E '^<tr ' | \
while read line; do
	## This does sparse sampling, but since the result has already been randomized, it seems redundant
	if [ "$sampleTracks" == "yes" -a $(( i % tracksQuotient )) -ne 0 ]; then
		i=$((i+1))
		continue
	fi
	#if [ "$sampleTracks" == "yes" -a $i -gt $tracksOut ]; then
	#	continue
	#fi
	artist=`echo $line | sed -r 's|.*/([^/]+)/_/([^/^"]+)".*|\1|' | sed 's|\+| |g' | awk '{print tolower($0)}' | urldecode`
	artist=`echo "$artist" | recode html..unicode | tr -d '\0'`
	artist_encoded=`echo $artist | sed 's|/| |g' | urlencode`
	track=`echo $line | sed -r 's|.*/([^/]+)/_/([^/^"]+)".*|\2|' | urldecode`
	track_encoded=`echo $track | sed 's|/| |g' | urlencode`
	#echo >&2
	#echo "Finding track $track by $artist" >&2
	#echo "https://api.spotify.com/v1/search?q=$track_encoded%20artist:$artist_encoded&type=track"
	url=`curl -H "Authorization: Bearer $spotify_token" -X GET "https://api.spotify.com/v1/search?q=$track_encoded%20artist:$artist_encoded&type=track" 2>/dev/null | \
	jq ".tracks.items[] | select(.artists[].name | ascii_downcase | contains(\"$artist\")) | .uri" | head -1 || continue`
	if [ -n "$url" ]; then
		if [ $i -ne 0 ];then
			echo -n ,
		fi
		echo -n $url | sed 's| |,|g'
		i=$((i+1))
	fi
done
echo -n "]"
