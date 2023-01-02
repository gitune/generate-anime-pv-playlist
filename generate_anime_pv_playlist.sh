#!/bin/bash

# please set API KEY etc. into following environment variables.
#   YOUTUBE_API_KEY
#   YOUTUBE_CLIENT_ID
#   YOUTUBE_CLIENT_SECRET
#   YOUTUBE_REFRESH_TOKEN
#   YOUTUBE_CHANNEL_ID

set -e
cd $(dirname $0)

# functions
getAllResults() {
    # getAllResults query latestAt(opt)
    local result
    local results
    local nextPageToken
    local olderExists

    results=""
    nextPageToken=""
    olderExists=""
    while
        if [[ -n "${nextPageToken}" ]]; then
            nextPageToken="&pageToken=${nextPageToken}"
        fi
        result=$(curl -s "$1${nextPageToken}")
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
    # global varibales "targets[]" and "playListItems" are needed
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
        filtered=$(echo "${playListItems}" | uconv -x '[\u3000,\uFF01-\uFF5D] Fullwidth-Halfwidth' | grep -in "${targets[$i]}")
        while IFS=$'\t' read -r numId title description publishedAt; do
            j=$(echo "${numId}" | cut -d':' -f1)
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

# ======== main ========

# removed video list
declare -A removed

# read channels ========
cResults=$(getAllResults "https://www.googleapis.com/youtube/v3/subscriptions?key=${YOUTUBE_API_KEY}&part=snippet&channelId=${YOUTUBE_CHANNEL_ID}&maxResults=50&order=alphabetical")
#cResults=$(cat subscriptions.json) # for test
echo "${cResults}" >subscriptions.json
echo "${cResults}" | jq -r '.items[]|[.snippet.resourceId.channelId,.snippet.title]|@tsv' >channels.tsv
echo "count(channels)=$(cat channels.tsv | wc -l)"

declare -A channelId
channelQuery=""
d=""
while IFS=$'\t' read -r id name; do
    channelId[${id}]=1
    channelQuery="${channelQuery}${d}\"${name}\""
    d="|" 
done <channels.tsv

# build query ========
#q=$(echo "アニメ PV|CM|TVCM|OP|オープニング|ED|エンディング ${channelQuery}" | jq -Rr '@uri')
q=$(echo "アニメ PV|CM|TVCM|OP|オープニング|ED|エンディング" | jq -Rr '@uri')

# search ========
# use latest
#if [[ ! -f search_results.tsv ]]; then
#    jq -rn "now - (86400 * 30)|[todate,\"dummyId\",\"dummyCid\",\"dummyTitle\",\"dummyDesc\"]|@tsv" >>search_results.tsv
#fi
#latestPublishedAt=$(tail -1 search_results.tsv | cut -f1)
# use 1 month ago
latestPublishedAt=$(jq -rn "now - (86400 * 30)|todate")
sResults=$(getAllResults "https://www.googleapis.com/youtube/v3/search?key=${YOUTUBE_API_KEY}&part=snippet&maxResults=50&order=date&type=video&q=${q}" ${latestPublishedAt})
#sResults=$(cat search_results.json) # for test
echo "${sResults}" >search_results.json
echo "${sResults}" | jq -r '.items[]|[.snippet.publishedAt,.id.videoId,.snippet.channelId,.snippet.title,.snippet.description]|@tsv' >search_results.tsv.all
# filter videos in official channels only
while IFS=$'\n' read line; do
    cid=$(echo "${line}" | cut -f3)
    if [[ -n "${channelId[${cid}]}" ]]; then
        echo "${line}" >>search_results.tsv.tmp
    fi
done <search_results.tsv.all
cat search_results.tsv search_results.tsv.tmp | sort | uniq >search_results.tsv.new
rm search_results.tsv search_results.tsv.tmp search_results.tsv.all
mv search_results.tsv.new search_results.tsv

# process per each playlist ========
accessToken=$(getAccessToken)
for playListFile in $(ls playlist_*.txt); do
    # save old playlist data if exists
    if [[ -f ${playListFile}.json ]]; then
        mv -f ${playListFile}.json ${playListFile}.json.old
        #cp ${playListFile}.json.old ${playListFile}.json # for test
    fi
    # read current playlist
    playlistId=$(cat ${playListFile} | head -1)
    plResults=$(getAllResults "https://www.googleapis.com/youtube/v3/playlistItems?key=${YOUTUBE_API_KEY}&part=snippet&maxResults=50&playlistId=${playlistId}")
    #plResults=$(cat ${playListFile}.json) # for test
    echo "${plResults}" >${playListFile}.json
    playListItems=$(echo "${plResults}" | jq -r '.items[]|[.snippet.resourceId.videoId,.snippet.title,.snippet.description,.snippet.publishedAt]|@tsv')
    echo "${playListFile}, count(playListItems)=$(echo "${playListItems}" | wc -l)"
    # update removed video list
    if [[ -f ${playListFile}.json.old ]]; then
        cat ${playListFile}.json.old | jq -r '.items[]|.snippet.resourceId.videoId' | sort | uniq >${playListFile}.json.old.ids
        cat ${playListFile}.json | jq -r '.items[]|.snippet.resourceId.videoId' | sort | uniq >${playListFile}.json.ids
        diff ${playListFile}.json.old.ids ${playListFile}.json.ids | egrep "^<" | sed -r 's/^< (.*)$/\1/' >removed.txt.tmp
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
    targetList=$(sed 1d ${playListFile})
    targets=()
    while read t; do
        nTarget=$(echo "${t}" | uconv -x '[\u3000,\uFF01-\uFF5D] Fullwidth-Halfwidth')
        targets+=("${nTarget}")
    done <<EOT
${targetList}
EOT
    offset=0
    # check new videos
    addResult=""
    for i in ${!targets[@]}; do
        tail -1000 search_results.tsv | tac | uconv -x '[\u3000,\uFF01-\uFF5D] Fullwidth-Halfwidth' | \
        grep -i "${targets[$i]}" | egrep -i "PV|CM|OP|オープニング|ED|エンディング" | \
        while IFS=$'\t' read -r publishedAt id cId title description; do
            if [[ -n "${removed[${id}]}" ]]; then
                echo "skip ${targets[$i]}, id=${id}"
                continue
            fi
            pos=$(assumePosition ${i} ${id} ${publishedAt})
            if [[ pos -ge 0 ]]; then
                # insert video to playlist
                echo "found ${targets[$i]}, id=${id}, assumePosition=$((${pos} + ${offset}))"
                addResult=$(curl -s -H "Content-Type: application/json" -H "Authorization: Bearer ${accessToken}" -d "{\"snippet\":{\"playlistId\":\"${playlistId}\",\"resourceId\":{\"videoId\":\"${id}\",\"kind\":\"youtube#video\"},\"position\":${pos}}}" "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet")
                echo "${addResult}" >>add_results.json
                offset=$(($offset + 1))
            else
                echo "exist ${targets[$i]}, id=${id}"
            fi
        done
    done
    if [[ -n "${addResult}" ]]; then
        # save updated playlist
        plResults=$(getAllResults "https://www.googleapis.com/youtube/v3/playlistItems?key=${YOUTUBE_API_KEY}&part=snippet&maxResults=50&playlistId=${playlistId}")
        #plResults=$(cat ${playListFile}.json) # for test
        echo "${plResults}" >${playListFile}.json
    fi
done

