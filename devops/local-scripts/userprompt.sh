
read -p "Enter your GitHub personal access token: " SCRIPT_GIT_TOKEN
export SCRIPT_GIT_TOKEN
env | grep '^SCRIPT_GIT_TOKEN='