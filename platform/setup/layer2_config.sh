#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DIRECTORY="$1"
source "${DIRECTORY}"/config/subnet_config.sh

# read configs
readarray groups < "${DIRECTORY}"/config/AS_config.txt
readarray routers < "${DIRECTORY}"/config/router_config.txt
readarray l2_switches < "${DIRECTORY}"/config/layer2_switches_config.txt
readarray l2_links < "${DIRECTORY}"/config/layer2_links_config.txt
readarray l2_hosts < "${DIRECTORY}"/config/layer2_hosts_config.txt

group_numbers=${#groups[@]}
n_routers=${#routers[@]}
n_l2_switches=${#l2_switches[@]}
n_l2_links=${#l2_links[@]}
n_l2_hosts=${#l2_hosts[@]}


# Layer2 connectivity
for ((k=0;k<group_numbers;k++)); do
    group_k=(${groups[$k]})
    group_number="${group_k[0]}"
    group_as="${group_k[1]}"
    group_config="${group_k[2]}"

    if [ "${group_as}" != "IXP" ];then

        declare -A l2_id
        declare -A l2_routerid

        # Initialization of the associative arrays
        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            property2="${router_i[2]}"
            l2_id[$property2]=0
            l2_routerid[$property2]=1
        done

        idtmp=1
        for ((i=0;i<n_routers;i++)); do
            router_i=(${routers[$i]})
            rname="${router_i[0]}"
            property1="${router_i[1]}"
            property2="${router_i[2]}"
            if [[ "${property2}" == *L2* ]];then

                declare -A vlanset
                declare -A vlanl2set
                for ((l=0;l<n_l2_hosts;l++)); do
                    host_l=(${l2_hosts[$l]})
                    vlan="${host_l[5]}"
                    vlanset[$vlan]=0
                    vlanl2set[${property2}-${vlan}]=0
                done

                if [[ ${l2_id[$property2]} -eq 0 ]]; then
                    l2_id[$property2]=$idtmp
                    idtmp=$(($idtmp+1))
                fi

                for vlan in "${!vlanset[@]}"
                do
                    subnet_router="$(subnet_l2 ${group_number} $((${l2_id[$property2]}-1)) ${vlan} ${l2_routerid[$property2]})"

                    docker exec -d ${group_number}_${rname}router \
                        vconfig add ${rname}-L2 $vlan

                    if [ "$group_config" == "Config" ]; then
                        docker exec -d ${group_number}_${rname}router \
                            vtysh -c 'conf t' -c 'interface '${rname}'-L2.'$vlan -c 'ip address '$subnet_router
                    fi
                done

                l2_routerid[$property2]=$((${l2_routerid[$property2]}+1))
            fi
        done

        for ((l=0;l<n_l2_hosts;l++)); do
            host_l=(${l2_hosts[$l]})
            hname="${host_l[0]}"
            l2name="${host_l[1]}"
            sname="${host_l[2]}"
            throughput="${host_l[3]}"
            delay="${host_l[4]}"
            vlan="${host_l[5]}"

            if [ "$group_config" == "Config" ]; then
                docker exec -d "${group_number}""_L2_""${l2name}_${sname}" \
                    ovs-vsctl set port ${group_number}-$hname tag=$vlan
            fi

            if [[ $hname != vpn* ]]; then
                if [ "$group_config" == "Config" ]; then
                    subnet_host=$(subnet_l2 $group_number $((${l2_id["L2-"$l2name]}-1)) $vlan $((${vlanl2set["L2-"${l2name}-${vlan}]}+${l2_routerid["L2-"$l2name]})))

                    docker exec -d ${group_number}_L2_${l2name}_${hname} \
                        ifconfig ${group_number}-${sname} $subnet_host up

                    subnet_gw="$(subnet_l2 ${group_number} $((${l2_id["L2-"$l2name]}-1)) ${vlan} 1)"

                    docker exec -d ${group_number}_L2_${l2name}_${hname} \
                        route add default gw ${subnet_gw%/*}
                fi
            fi

            vlanl2set["L2-"${l2name}-${vlan}]=$((${vlanl2set["L2-"${l2name}-${vlan}]}+1))
        done

        trunk_string=''
        for v in "${!vlanset[@]}"
        do
            trunk_string=${trunk_string}${v},
        done

        for ((l=0;l<n_l2_links;l++)); do
            row_l=(${l2_links[$l]})
            l2name1="${row_l[0]}"
            switch1="${row_l[1]}"
            l2name2="${row_l[2]}"
            switch2="${row_l[3]}"
            throughput="${row_l[4]}"
            delay="${row_l[5]}"

            if [ "$group_config" == "Config" ]; then
                docker exec -d "${group_number}""_L2_""${l2name1}_${switch1}" \
                    ovs-vsctl set port ${group_number}-${switch2} trunks=${trunk_string::-1}

                docker exec -d "${group_number}""_L2_""${l2name2}_${switch2}" \
                    ovs-vsctl set port ${group_number}-${switch1} trunks=${trunk_string::-1}
            fi
        done

        for ((l=0;l<n_l2_switches;l++)); do
            switch_l=(${l2_switches[$l]})
            switch_l=(${l2_switches[$l]})
            l2name="${switch_l[0]}"
            sname="${switch_l[1]}"
            connected="${switch_l[2]}"
            sys_id="${switch_l[3]}"

            if [ "$group_config" == "Config" ]; then
                if [[ $connected != "N/A" ]]; then
                    docker exec -d "${group_number}""_L2_""${l2name}_${sname}" \
                        ovs-vsctl set port ${connected}router trunks=${trunk_string::-1}
                fi
            fi
        done
    fi
done
