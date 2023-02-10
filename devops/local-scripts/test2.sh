#!/bin/bash

get_label() {
  local name="$1"
  local ref_type="$2"
  local sha="$3"
  local label
  if [ "$ref_type" == "repo" ]; then
    label="$name-$sha"
  else
    label="$name"
  fi
  echo "$label"
}

function get_sha {
  local repo_name="$1"
  local branch="$2"

  if [ -n "$branch" ]; then
    echo "$branch"
  else
    local api_url="https://api.github.com/repos/${repo_name}"
    local headers="Accept: application/vnd.github+json"
    local auth_token="Authorization: token $SCRIPT_GIT_TOKEN"
    local curl_result=$(curl -H "$headers" -H "$auth_token" "$api_url")
    local sha=$(curl -H "$headers" -H "$auth_token" "$api_url" | grep '"sha"' | head -n 1 | cut -d '"' -f 4 | cut -c1-7)
    
    if [ -z "$sha" ]; then
        exit 4
    fi

    echo "$sha"
  fi
}

function get_github_file {
  local repo="$1"
  local file_path="$2"
  local sha="$3"

  local repo_segment=$(echo $repo_name | sed 's:/branches.*$::')
  
  local api_url="https://api.github.com/repos/$repo_segment/contents/service-root/$file_path?ref=$sha"
  local headers="Accept: application/vnd.github+json"
  local auth_token="Authorization: token $SCRIPT_GIT_TOKEN"

  echo $(curl -H "$headers" -H "$auth_token" "$api_url")
}

function get_and_modify_dockerfile {
  local path="$1"
  local implementation="$2"
  local reference_type="$3"
  local repo_name="$4"
  local sha="$5"

  local dockerfile=""

  if [ "$reference_type" = "repo" ]; then

    local repo_segment=$(echo $repo_name | sed 's:/branches.*$::')

    local GITHUB_TOKEN=$SCRIPT_GIT_TOKEN

    # Get the Dockerfile from the repository
    response=$(get_github_file "$repo_name" "$implementation.Dockerfile" "$sha")
    dockerfile=$(echo "$response" | jq -r '.content' | base64 -d)
    dockerfile="$dockerfile"$'\n'""
    dockerfile="$dockerfile"$'\n'"ENV GIT_TOKEN='$GITHUB_TOKEN'"
    dockerfile="$dockerfile"$'\n'"ENV REPO_SEGMENT='$repo_segment'"
    dockerfile="$dockerfile"$'\n'"ENV REPO_SHA='$sha'"
    dockerfile="$dockerfile"$'\n'"WORKDIR /app/services"
    dockerfile="$dockerfile"$'\n''RUN wget --header="Authorization: token ${GIT_TOKEN}" "https://api.github.com/repos/${REPO_SEGMENT}/tarball/${REPO_SHA}" -O - | tar -xzvf - --strip-components=3 casper-ultimate-test-docker-push-${REPO_SHA}/service-root/'$implementation
    dockerfile="$dockerfile"$'\n''RUN echo ${GIT_TOKEN}'
    dockerfile="$dockerfile"$'\n''RUN cat readme.md'
  else
    # Append the necessary content to the local Dockerfile
    dockerfile=$(cat "$path/$implementation.Dockerfile")
    dockerfile="$dockerfile"$'\n'"WORKDIR /app/services"
  fi

  echo "$dockerfile"
}

function create_docker_image {
  local path="$1"
  local implementation="$2"
  local label="$3"
  local reference_type="$4"
  local repo_name="$5"
  local sha="$6"
  local rebuild="$7"

  local image_exists=$(docker images -q "$label")

  if [ -z "$image_exists" ] || [ "$rebuild" = true ]; then
    local dockerfile=$(get_and_modify_dockerfile "$path" "$implementation" "$reference_type" "$repo_name" "$sha")
    echo "$dockerfile" | docker build --no-cache -t "$label" -
  else
    echo "Image with label $label already exists"
  fi
}

input_file="../input.json"
array=()

while read -r line; do
  name=$(jq -r '.ServiceName' <<< "$line")
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]')

  reference_type=$(jq -r '.ReferenceType' <<< "$line")
  repo_name=""
  sha=""
  path=""
  implementation=""

  if [ "$reference_type" == "repo" ]; then
    repo_name=$(jq -r '.ServiceRepo.name' <<< "$line")
    sha=$(jq -r '.ServiceRepo.sha' <<< "$line")
    sha=$(get_sha "$repo_name" "$sha")
    if [ -z "$sha" ]; then
        echo "my_function encountered an error"
        exit 1
    fi
    implementation=$(jq -r '.ServiceRepo.implementation' <<< "$line")
    path="$repo_name/service-root/$implementation"
  else
    path=$(jq -r '.ServiceData.path' <<< "$line")
    implementation=$(jq -r '.ServiceData.implementation' <<< "$line")
  fi

  label=$(get_label "$name" "$reference_type" "$sha")
  label=$(echo "$label" | tr '[:upper:]' '[:lower:]')
  echo $label
  rebuild=false
  if [ "$reference_type" == "local" ]; then
    rebuild=true
  fi

  create_docker_image "$path" "$implementation" "$label" "$reference_type" "$repo_name" "$sha" "true"
  
  obj=$(jq -n  '{"name": "'"${name}"'", "label": "'"${label}"'"}')
  array+=("$obj")
done < <(jq -c '.[]' "$input_file")

echo "${array[@]}" | jq -c '.'