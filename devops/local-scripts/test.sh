#!/bin/bash

input_file="../input.json"
array=()

get_label() {
  local line=$1
  local name=$(jq -r '.ServiceName' <<< "$line")
  local ref_type=$(jq -r '.ReferenceType' <<< "$line")
  local label
  if [ "$ref_type" == "repo" ]; then
    local repo_url=$(jq -r '.ServiceRepo.name' <<< "$line")
    local sha=$(jq -r '.ServiceRepo.sha' <<< "$line")
    label="$name-$sha"
  else
    local path=$(jq -r '.ServiceData.path' <<< "$line")
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
    dockerfile=$(git -C "$repo_name" show "$sha:$implementation.Dockerfile")
    # Append the necessary content to the Dockerfile based on the implementation
    dockerfile="$dockerfile"$'\n'"RUN cd /app/services/${repo_name} && git checkout $sha && cd $implementation && pwd && ls"
  else
    # Append the necessary content to the local Dockerfile
    dockerfile=$(cat "$path/$implementation.Dockerfile")
  fi
  
  echo "$dockerfile"
}

while read -r line; do
  name=$(jq -r '.ServiceName' <<< "$line")
  label=$(get_label "$line")
  name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
  label=$(echo "$label" | tr '[:upper:]' '[:lower:]')

  reference_type=$(jq -r '.ReferenceType' <<< "$line")
  repo_name=""
  sha=""
  path=""
  implementation=""

  if [ "$reference_type" == "repo" ]; then
    repo_name=$(jq -r '.ServiceRepo.name' <<< "$line")
    sha=$(jq -r '.ServiceRepo.sha' <<< "$line")
    implementation=$(jq -r '.ServiceRepo.implementation' <<< "$line")
    path="$repo_name/service-root/$implementation"
  else
    path=$(jq -r '.ServiceData.path' <<< "$line")
    implementation=$(jq -r '.ServiceData.implementation' <<< "$line")
  fi

  rebuild=false
  if [ "$reference_type" == "local" ]; then
    rebuild=true
  fi

  create_docker_image "$path" "$implementation" "$label" "$reference_type" "$repo_name" "$sha" "$rebuild"

  obj=$(jq -n  '{"name": "'"${name}"'", "label": "'"${label}"'"}')
  array+=("$obj")
done < <(jq -c '.[]' "$input_file")

echo "${array[@]}" | jq -c '.'