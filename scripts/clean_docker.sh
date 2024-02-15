#!/bin/bash

# Define the word to filter by
WORD="import"
# WORD="frontend"
# WORD="person-registry"

# Check if any word is provided
if [[ -z "$WORD" ]]; then
  echo "Error: Please provide a word to filter images by."
  exit 1
fi

# echo "Removing images containing '$WORD':"
# # echo "$image_ids" | xargs -I {} sudo docker rmi --force {}
# echo "$image_ids" | xargs -I {} sudo docker image prune {}
#
# echo "Done!"



images_infos=$(sudo docker images --filter "reference=*${WORD}*" --format "{{.ID}} {{.Repository}} {{.Tag}}")
image_ids=$(sudo docker images --filter "reference=*${WORD}*" --format "{{.ID}}")
image_names=$(sudo docker images --filter "reference=*${WORD}*" --format "{{.Repository}}")
image_tags=$(sudo docker images --filter "reference=*${WORD}*" --format "{{.Tag}}")

for id in $image_ids; do
	echo "$id"
  sudo docker stop $(sudo docker ps -a -f "ancestor=$id" --format {{.ID}})
  sudo docker rm $(sudo docker ps -a -f "ancestor=$id" --format {{.ID}})
  sudo docker rmi "$id"
done
