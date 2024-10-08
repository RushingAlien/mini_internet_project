#!/bin/bash
#
# Save and collect configuration for all groups.

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

OUTPUT_DIR=${2:-"${DIRECTORY}/groups/saved_configs"}
mkdir -p $OUTPUT_DIR

SUFFIX=$(date --iso-8601=seconds)

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt

n_groups=${#groups[@]}

echo "Dump all configs."
for ((k=0;k<n_groups;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"

    # Hack while 51 does not respond.
    if [ "${group_number}" == 51 ]; then
        continue
    fi

    #echo $group_number
    if [ "${group_as}" != "IXP" ];then
        # Save configs with suffix to separate it from other configs.
        docker exec -t "${group_number}_ssh" ./root/save_configs.sh "$SUFFIX" > /dev/null &
    fi
done
wait

echo "Download configs from containers into: $OUTPUT_DIR"
for ((k=0;k<n_groups;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"

    if [ "${group_as}" != "IXP" ];then
        docker cp "${group_number}_ssh:/configs_${SUFFIX}/." "${OUTPUT_DIR}/g${group_number}" > /dev/null &
    fi
done
wait

echo "Cleanup."
for ((k=0;k<n_groups;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"

    if [ "${group_as}" != "IXP" ];then
        docker exec "${group_number}_ssh" rm -rf /configs_${SUFFIX} /configs_${SUFFIX}.tar.gz > /dev/null &
    fi
done
wait
