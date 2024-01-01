#!/bin/bash

# please set API KEY etc. into following environment variables.
#   YOUTUBE_API_KEY
#   YOUTUBE_CLIENT_ID
#   YOUTUBE_CLIENT_SECRET
#   YOUTUBE_REFRESH_TOKEN

set -e
cd $(dirname $0)

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

getAccessToken() {
    # getAccessToken
    # required environment variables: YOUTUBE_CLIENT_ID, YOUTUBE_CLIENT_SECRET, YOUTUBE_REFRESH_TOKEN
    local result

    result=$(curl -s -H "Content-Type: application/json" -d "{refresh_token:\"${YOUTUBE_REFRESH_TOKEN}\",client_id:\"${YOUTUBE_CLIENT_ID}\",client_secret:\"${YOUTUBE_CLIENT_SECRET}\",redirect_uri:\"http://localhost:8000\",grant_type:\"refresh_token\"}" https://accounts.google.com/o/oauth2/token)
    echo $(echo "${result}" | jq -r .access_token)
}

# ======== main ========

if [[ $# -lt 1 ]]; then
    echo "$0 playlistId" >/dev/stderr
    exit 1
fi

echo "$(date --iso-8601=seconds) START removing private videos from a playlist($1). ========"

# get playlist items
echo "read playlist items..."
result=$(getAllResults "https://www.googleapis.com/youtube/v3/playlistItems?key=${YOUTUBE_API_KEY}&playlistId=$1&part=snippet&maxResults=50")
playlistItems=$(echo "${result}" | jq -r '.items[]|[.snippet.resourceId.videoId,.snippet.title,.snippet.description,.snippet.publishedAt,.id]|@tsv')

# remove private videos
accessToken=$(getAccessToken)
while IFS=$'\t' read -r videoId title description publishedAt id; do
    if [[ "${title}" == "Private video" && "${description}" == "This video is private." ]]; then
        echo "removed id=${videoId}"
        curl -s --compressed -X DELETE -H "Authorization: Bearer ${accessToken}" -o - "https://www.googleapis.com/youtube/v3/playlistItems?id=${id}" >>removal_results.json.log 2>&1 # commented for test
    fi
done <<EOT
${playlistItems}
EOT
