#!/bin/bash
# please set the following environment variables.
#   YOUTUBE_CLIENT_ID
#   YOUTUBE_CLIENT_SECRET

if [[ $# -lt 1 ]]; then
    echo "Firstly please input the following URL into your browser and get auth code."
    echo "https://accounts.google.com/o/oauth2/auth?client_id=${YOUTUBE_CLIENT_ID}&redirect_uri=http%3A%2F%2Flocalhost%3A8000&scope=https://www.googleapis.com/auth/youtube&response_type=code&access_type=offline" >/dev/stderr
    echo "Then, please rerun this script with auth code." >/dev/stderr
    exit 1
fi
curl -H "Content-Type: application/json" -d "{code:\"$1\",client_id:\"${YOUTUBE_CLIENT_ID}\",client_secret:\"${YOUTUBE_CLIENT_SECRET}\",redirect_uri:\"http://localhost:8000\",grant_type:\"authorization_code\"}" https://accounts.google.com/o/oauth2/token
