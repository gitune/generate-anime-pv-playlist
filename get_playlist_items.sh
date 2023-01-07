#!/bin/bash

# please set API KEY etc. into following environment variables.
#   YOUTUBE_API_KEY

set -e

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

# ======== main ========

if [[ $# -lt 1 ]]; then
    echo "$0 playlistId" >/dev/stderr
    exit 1
fi
echo $(getAllResults "https://www.googleapis.com/youtube/v3/playlistItems?key=${YOUTUBE_API_KEY}&playlistId=$1&part=snippet&maxResults=50")
