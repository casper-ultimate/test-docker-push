#!/bin/bash

input_file="../input.json"
array=()

function get_sha {
  local repo_name="$1"
  local branch="$2"

  if [ -n "$branch" ]; then
    echo "$branch"
  else
    local api_url="https://api.github.com/repos/${repo_name}"
    local headers="Accept: application/vnd.github+json"
    local auth_token="Authorization: token ${GITHUB_TOKEN}"

    local sha=$(curl  "$api_url" | jq -r '.commit.sha')
    echo "$sha"
  fi
}

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

function create_docker_image {
  local path="$1"
  local implementation="$2"
  local label="$3"
  local reference_type="$4"
  local repo_name="$5"
  local sha="$6"
  local rebuild="$7"
  
  local existing_image=$(docker images -q "$label")
  
  if [ -z "$existing_image" ] || [ "$rebuild" = "true" ]; then
    local dockerfile=$(get_and_modify_dockerfile "$path" "$implementation" "$label" "$reference_type" "$repo_name" "$sha")
    
    if [ "$rebuild" = "true" ]; then
      echo "$dockerfile" | docker build --no-cache -t "$label" -
    else
      echo "$dockerfile" | docker build -t "$label" -
    fi
  else
    echo "Image with label $label already exists, use the --rebuild flag to force rebuild"
  fi
}

function get_and_modify_dockerfile {
  local path="$1"
  local implementation="$2"
  local label="$3"
  local reference_type="$4"
  local repo_name="$5"
  local sha="$6"
  
  local dockerfile=""
  if [ "$reference_type" = "repo" ]; then
    # Get the Dockerfile from the repository
    repo_segment=$(echo $repo_name | sed 's:/branches.*$::')
    $repo_segment
    dockerfile=$(git -C "https://api.github.com/repos/$repo_segment" show "$sha:service-root/$implementation.Dockerfile")
    # Append the necessary content to the Dockerfile based on the implementation
    #dockerfile="$dockerfile"$'\n'"RUN cd /app/services && git checkout $sha && cd ./service-root && pwd && ls"
  else
    # Append the necessary content to the local Dockerfile
    dockerfile=$(cat "$path/$implementation.Dockerfile")
  fi
  
  echo "$dockerfile"
}

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

  create_docker_image "$path" "$implementation" "$label" "$reference_type" "$repo_name" "$sha" "$rebuild"

  obj=$(jq -n  '{"name": "'"${name}"'", "label": "'"${label}"'"}')
  array+=("$obj")
done < <(jq -c '.[]' "$input_file")

echo "${array[@]}" | jq -c '.'