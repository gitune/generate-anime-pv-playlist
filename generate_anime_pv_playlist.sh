#!/bin/bash

# please set API KEY etc. into following environment variables.
#   YOUTUBE_API_KEY
#   YOUTUBE_CLIENT_ID
#   YOUTUBE_CLIENT_SECRET
#   YOUTUBE_REFRESH_TOKEN
#   YOUTUBE_CHANNEL_ID

set -e
cd $(dirname $0)

# constants
KEYWORDS="PV|CM|OP|オープニング|ED|エンディング|紹介映像|ティザー映像"

# functions
getAllResults() {
    # getAllResults query latestAt(opt)
    local result
    local results
    local nextPageToken
    local oldest
    local olderExists

    results=""
    nextPageToken=""
    olderExists=""
    while
        if [[ -n "${nextPageToken}" ]]; then
            nextPageToken="&pageToken=${nextPageToken}"
        fi
        result=$(curl -s --compressed "$1${nextPageToken}")
        results="${results}${result}"
        nextPageToken=$(echo "${result}" | jq -r .nextPageToken)
        if [[ -n "$2" ]]; then
            oldest=$(echo "${result}" | jq -r '.items[]|.snippet.publishedAt' | sort | head -1)
            if [[ "$2" > "${oldest}" ]]; then
                olderExists=1
            fi
        fi
        test "${nextPageToken}" != "null" -a -z "${olderExists}"
    do
        sleep 1
    done
    echo "${results}"
}

assumePosition() {
    # assumePosition targetIndex videoId publishedAt
    # global varibales "targets[]" and "playlistItems" are needed
    local prev
    local i
    local j
    local id
    local title
    local description
    local publishedAt
    local filtered

    prev="-1"
    for i in $(seq $1 -1 0); do
        # playlistをスキャンして自分の前のPVを探す
        filtered=$(echo "${playlistItems}" | uconv -x '[\u3000,\uFF01-\uFF5D] Fullwidth-Halfwidth' | \
            grep -in "${targets[$i]}" | cat) # avoid exit when no result
        while IFS=$'\t' read -r numId title description publishedAt; do
            if [[ -z "${numId}" ]]; then
                # no result
                break
            fi
            j=$(echo "${numId}" | cut -d':' -f1)
            j=$((j - 1)) # to be 0 origin
            id=$(echo "${numId}" | cut -d':' -f2)
            if [[ "$2" == "${id}" ]]; then
                echo "-1"
                return
            elif [[ $1 -ne $i || "$3" > "${publishedAt}" ]]; then
                if [[ prev -lt j ]]; then
                    prev=${j}
                fi
            fi
        done <<EOT
${filtered}
EOT
    done
    echo $((prev + 1))
}

getAccessToken() {
    # getAccessToken
    # required environment variables: YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN
    local result

    result=$(curl -s -H "Content-Type: application/json" -d "{refresh_token:\"${YOUTUBE_REFRESH_TOKEN}\",client_id:\"${YOUTUBE_CLIENT_ID}\",client_secret:\"${YOUTUBE_CLIENT_SECRET}\",redirect_uri:\"http://localhost:8000\",grant_type:\"refresh_token\"}" https://accounts.google.com/o/oauth2/token)
    echo $(echo "${result}" | jq -r .access_token)
}

updatePlaylists() {
    # updatePlaylists playlistId playlistFile
    # this function updates a global variable "playlistItems"
    local result

    result=$(getAllResults "https://www.googleapis.com/youtube/v3/playlistItems?key=${YOUTUBE_API_KEY}&part=snippet&maxResults=50&playlistId=$1")
    #result=$(cat $2.json) # for test
    echo "${result}" >$2.json
    playlistItems=$(echo "${result}" | jq -r '.items[]|[.snippet.resourceId.videoId,.snippet.title,.snippet.description,.snippet.publishedAt]|@tsv')
    echo "$2, count(playlistItems)=$(echo "${playlistItems}" | wc -l)"
}

# ======== main ========

# removed video list
declare -A removed

# read channels & videos ========
cResults=$(getAllResults "https://www.googleapis.com/youtube/v3/subscriptions?key=${YOUTUBE_API_KEY}&part=snippet&channelId=${YOUTUBE_CHANNEL_ID}&maxResults=50&order=alphabetical")
#cResults=$(cat subscriptions.json) # for test
echo "${cResults}" >subscriptions.json
echo "${cResults}" | jq -r '.items[]|[.snippet.resourceId.channelId,.snippet.title]|@tsv' >channels.tsv
echo "count(channels)=$(cat channels.tsv | wc -l)"

# use 2 days ago
latestPublishedAt=$(jq -rn "now - (86400 * 2)|todate")

if [[ -s search_results.json ]]; then
    mv -f search_results.json search_results.json.old
fi
while IFS=$'\t' read -r cId cName; do
    echo "get videos on ${cName}"
    cDetails=$(getAllResults "https://www.googleapis.com/youtube/v3/channels?key=${YOUTUBE_API_KEY}&id=${cId}&part=contentDetails")
    uploads=$(echo "${cDetails}" | jq -r '.items[]|.contentDetails.relatedPlaylists.uploads')
    while read plId; do
        if [[ -z "${plId}" ]]; then
            break
        fi
        sResults=$(getAllResults "https://www.googleapis.com/youtube/v3/playlistItems?key=${YOUTUBE_API_KEY}&playlistId=${plId}&part=snippet&maxResults=50" ${latestPublishedAt})
        echo "${sResults}" >>search_results.json
        echo "${sResults}" | jq -r ".items[]|select((.snippet.title|test(\"#shorts\";\"i\")|not) and (.snippet.title|test(\"(${KEYWORDS})\";\"i\")))|[.snippet.publishedAt,.snippet.resourceId.videoId,.snippet.title,.snippet.description]|@tsv" >>search_results.tsv.tmp
    done <<EOT
${uploads}
EOT
done <channels.tsv
cat search_results.tsv search_results.tsv.tmp | sort | uniq >search_results.tsv.new
rm -f search_results.tsv search_results.tsv.tmp
mv search_results.tsv.new search_results.tsv

# process per each playlist ========
accessToken=$(getAccessToken)
for playlistFile in $(ls playlist_*.txt); do
    # save old playlist data if exists
    if [[ -f ${playlistFile}.json ]]; then
        mv -f ${playlistFile}.json ${playlistFile}.json.old
        #cp ${playlistFile}.json.old ${playlistFile}.json # for test
    fi
    # read current playlist
    playlistId=$(cat ${playlistFile} | head -1)
    updatePlaylists "${playlistId}" "${playlistFile}"
    # update removed video list
    if [[ -f ${playlistFile}.json.old ]]; then
        cat ${playlistFile}.json.old | jq -r '.items[]|.snippet.resourceId.videoId' | sort | uniq >${playlistFile}.json.old.ids
        cat ${playlistFile}.json | jq -r '.items[]|.snippet.resourceId.videoId' | sort | uniq >${playlistFile}.json.ids
        diff ${playlistFile}.json.old.ids ${playlistFile}.json.ids | egrep "^<" | sed -r 's/^< (.*)$/\1/' >removed.txt.tmp
        if [[ -f removed.txt ]]; then
            mv -f removed.txt removed.txt.old
            cat removed.txt.old removed.txt.tmp | sort | uniq >removed.txt
        else
            cat removed.txt.tmp | sort | uniq >removed.txt
        fi
        rm -f *.ids removed.txt.old removed.txt.tmp
    fi
    # read removed video list
    if [[ -f removed.txt ]]; then
        while read line; do
            removed[${line}]=1
        done <removed.txt
    fi
    # read targets
    targetList=$(sed 1d ${playlistFile})
    targets=()
    while read t; do
        nTarget=$(echo "${t}" | uconv -x '[\u3000,\uFF01-\uFF5D] Fullwidth-Halfwidth')
        targets+=("${nTarget}")
    done <<EOT
${targetList}
EOT
    # check new videos
    for i in ${!targets[@]}; do
        searchResults=$(tail -1000 search_results.tsv | uconv -x '[\u3000,\uFF01-\uFF5D] Fullwidth-Halfwidth' | \
            grep -i "${targets[$i]}" | tac)
        while IFS=$'\t' read -r publishedAt id title description; do
            if [[ -z "${id}" ]]; then
                # no result
                break
            fi
            if [[ -n "${removed[${id}]}" ]]; then
                echo "skip ${targets[$i]}, id=${id}"
                continue
            fi
            pos=$(assumePosition ${i} ${id} ${publishedAt})
            if [[ pos -ge 0 ]]; then
                # insert video to playlist
                echo "found ${targets[$i]}, id=${id}, assumePosition=${pos}"
                addResult=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer ${accessToken}" -d "{\"snippet\":{\"playlistId\":\"${playlistId}\",\"resourceId\":{\"videoId\":\"${id}\",\"kind\":\"youtube#video\"},\"position\":${pos}}}" "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet") # commented for test
                echo "${addResult}" >>add_results.json
                updatePlaylists "${playlistId}" "${playlistFile}"
            else
                echo "exist ${targets[$i]}, id=${id}"
            fi
        done <<EOT
${searchResults}
EOT
    done
done

