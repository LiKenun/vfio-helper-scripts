#!/usr/bin/env bash

set -euo pipefail
shopt -s nullglob

getopt_command_available() {
    2>&1 getopt -T > /dev/null
    (($? == 4))
}

declare -r USAGE_TEXT="Usage:
\e[1m$0\e[0m [-h | --help | [-i | --iommu-groups I] [--max-precision D] [-m | --minimal] [--no-descriptions] [--no-headings] [--no-pci-bridges] [--no-resources] [--no-unique-ids] [--no-wrap] [--only-pci-devices] [--show-goodput] [--strip-pci-domain]]

Enumerate IOMMU groups and PCI devices within them, printing the output as a tree for each group, and \e[30m\e[103mhighlighting\e[0m any PCI devices bound to \e[1mvfio-pci\e[0m.

-h, --help              Display this usage text.
-i, --iommu-groups I    Enumerate only IOMMU groups I (e.g., '16' or '7,11,13').
    --max-precision D   Limit computed figures to at most D post-decimal digits.
-m, --minimal           Show the bare minimum needed to identify PCI devices.
    --no-descriptions   Hide descriptions of the devices.
    --no-headings       Hide column headings.
    --no-pci-bridges    Hide PCI bridges and groups which only contain them.
    --no-resources      Hide resource-related columns like lanes and link speed.
    --no-unique-ids     Hide unique identifiers like serial numbers.
    --no-wrap           Do not attempt to wrap the description column.
    --only-pci-devices  Do not enumerate anything below the PCI devices level.
    --show-goodput      Show the hypothetical goodput—throughput minus overhead.
    --strip-pci-domain  Use the 01:23.4 format when there’s only one PCI domain.

USB buses, ATA/NVMe/USB storage, and network interfaces under each PCI device are enumerated by default. The default columns include the device identifier (e.g., PCI slot or USB bus/device/interface number), vendor/product code, whether it’s resettable/removable, quantity of resources (e.g., lanes, ports, or storage capacity), throughput, bound driver, and description. Some output may be turned off individually with specific options. \e[1m-m\e[0m/\e[1m--minimal\e[0m cuts the output down to the bare minimum information needed to identify PCI devices.

For bus throughputs with known physical layer encoding overhead ratios, goodput is the throughput minus that. Standards such as USB and some classes of products built around them (e.g., storage adapters/enclosures) are typically marketed with their physical throughput. However, the physical throughput is an irrelevant detail for the purposes of determining how quickly an application can communicate data over the bus. Since the encoding overhead differs between bus types and their revisions, it’s also difficult to make comparisons between application layer speeds between different ones. The \e[1m--show-goodput\e[0m option shows an additional column of speeds which can be compared across different buses and their revisions. For example, USB 3.0’s “5 Gbps” will be given a parenthesized goodput of 4 Gbps.
$(getopt_command_available || printf '\n\e[1m\e[93mWarning:\e[0m command \e[1mgetopt\e[0m is unavailable. Providing any command line arguments will exit with error code \e[1m2\e[0m.')"

# Detect a request for help in command line arguments and handle it first, before requiring getopt for more complex parsing.
if (($# == 1))
then
    if [ "$@" = '--help' ] || [ "$@" = '-h' ]
    then
        >&2 echo -e "$USAGE_TEXT"
        exit 0
    elif [ "$@" = '--halp' ]
    then
        >&2 printf 'Usage: \e[5mlol no.\e[25m\n\n'
        exit 255
    fi
fi

# Parse other command line arguments if provided, or throw an error if the required getopt version is missing.
declare -A options=()
if (($# > 0))
then
    if getopt_command_available
    then
        eval set -- "$(getopt -n "$0" -o hi:m --long help,iommu-groups:,max-precision:,minimal,no-descriptions,no-headings,no-pci-bridges,no-resources,no-unique-ids,no-wrap,only-pci-devices,show-goodput,strip-pci-domain -- "$@")"
        while [ -n "${1-}" ]
        do
            case "$1" in
                --) # This option-ending marker will always be present. Ignore; we accept neither option values nor any other non-option arguments.
                    shift ;;
                -h|--help)
                    options[help]=1
                    shift ;;
                -i|--iommu-groups)
                    options[iommu-groups]="$2"
                    shift 2 ;;
                --max-precision)
                    options[max-precision]="$2"
                    shift 2 ;;
                -m|--minimal)
                    options[max-precision]="${options[max-precision]-0}"
                    options[minimal]=1
                    options[no-descriptions]=1
                    options[no-headings]=1
                    options[no-pci-bridges]=1
                    options[no-resources]=1
                    options[no-unique-ids]=1
                    options[only-pci-devices]=1
                    options[strip-pci-domain]=1
                    shift ;;
                --no-descriptions|--no-headings|--no-pci-bridges|--no-resources|--no-unique-ids|--no-wrap|--only-pci-devices|--show-goodput|--strip-pci-domain)
                    options["${1##--}"]=1
                    shift ;;
                *) # The first non-option argument after -- will trip on this case. Print the remaining arguments and exit.
                    >&2 echo "$0: other unrecognized arguments -- ${@@Q}"
                    >&2 echo -e "$USAGE_TEXT"
                    exit 3 ;;
            esac
        done
        if ((options[help]))
        then
            if ((${#options[@]} == 1))
            then
                >&2 echo -e "$USAGE_TEXT"
                exit 0
            else
                >&2 printf "\e[1m\e[91mError:\e[0m \e[1m-h\e[0m and \e[1m--help\e[0m may not be combined with other arguments.\n"
                exit 3
            fi
        fi
    else
        >&2 printf "\e[1m\e[91mError:\e[0m missing required command \e[1mgetopt\e[0m to parse command line arguments.\n"
        >&2  echo -e "$USAGE_TEXT"
        exit 2
    fi
fi

declare -r IOMMU_GROUPS_BASE_PATH='/sys/kernel/iommu_groups'
declare -r PCI_DOMAIN_BUS_PATH_PATTERN='/sys/devices/pci????:??'
declare -r PCI_DEVICE_BASE_PATH='/sys/bus/pci/devices'
declare -r PCI_BRIDGE_BASE_CLASS_CODE='0x06'
declare -r USB_DEVICE_BASE_PATH='/sys/bus/usb/devices'

declare -r -A SI_PREFIX_MAP=(    # Mapped to decimal exponents
    [Q]=30                       # Quetta-
    [R]=27                       # Ronna-
    [Y]=24                       # Yotta-
    [Z]=21                       # Zetta-
    [E]=18                       # Exa-
    [P]=15                       # Peta-
    [T]=12                       # Tera-
    [G]=9                        # Giga-
    [M]=6                        # Mega-
    [k]=3                        # Kilo-
)

declare -r -A PCIE_SPEED_MAP=(   # Mapped to goodput in Gbps
    ['2.5 GT/s PCIe']='2'        # Gen 1: 2.5 Gbps − 8b/10b overhead    = 2 Gbps
    ['5.0 GT/s PCIe']='4'        # Gen 2: 5 Gbps   − 8b/10b overhead    = 4 Gbps
    ['8.0 GT/s PCIe']='512/65'   # Gen 3: 8 Gbps   − 128b/130b overhead ≈ 7.88 Gbps
    ['16.0 GT/s PCIe']='1024/65' # Gen 4: 16 Gbps  − 128b/130b overhead ≈ 15.75 Gbps
    ['32.0 GT/s PCIe']='2048/65' # Gen 5: 32 Gbps  − 128b/130b overhead ≈ 31.51 Gbps
    ['64.0 GT/s PCIe']='121/2'   # Gen 6: 64 Gbps  − 242b/256b overhead = 60.5 Gbps
    ['128.0 GT/s PCIe']='121'    # Gen 7: 128 Gbps − 242b/256b overhead = 121 Gbps
)
declare -r -A USB_SPEED_MAP=(    # Mapped to goodput in Mbps
    ['1.5']='6/5'                # USB 1.0/1.1, Low Speed (LS):   1.5 Mbps − ~20% NRZI overhead ≈ 1.2 Mbps
    ['12']='48/5'                # USB 1.0/1.1, Full Speed (FS):  12 Mbps  − ~20% NRZI overhead ≈ 9.9 Mbps
    ['480']='400'                # USB 2.0, High Speed (HS):      480 Mbps − ~20% NRZI overhead ≈ 400 Mbps
    ['5000']='4000'              # USB 3.0, SuperSpeed (SS):      5 Gbps   − 8b/10b overhead    = 4 Gbps
                                 # USB 3.2, SuperSpeed two-lane (10 Gbps) is possible, but unprecedented.
    ['10000']='320000/33'        # USB 3.1, SuperSpeed+ (SS+):    10 Gbps  − 128b/132b overhead ≈ 9.7 Gbps
    ['20000']='640000/33'        # USB 3.2, SuperSpeed+ two-lane: 20 Gbps  − 128b/132b overhead ≈ 19.4 Gbps
)
declare -r -A SATA_SPEED_MAP=(   # Mapped to goodput in Gbps
    ['1.5 Gbps']='1.2'           # SATA revision 1.0, 1.5 Gbits/s: 1.5 Gbps − 8b/10b overhead = 1.2 Gbps
    ['3.0 Gbps']='2.4'           # SATA revision 2.0, 3 Gbits/s:   3 Gbps   − 8b/10b overhead = 2.4 Gbps
    ['6.0 Gbps']='4.8'           # SATA revision 3.0, 6 Gbits/s:   6 Gbps   − 8b/10b overhead = 4.8 Gbps
)

declare -r -a REQUIRED_COMMANDS=('bc' 'column' 'lspci')
declare -r -A OPTIONAL_COMMANDS=(
    [lsblk]='Some block device identifiers (e.g., serial numbers) may not be reported.'
    [lsusb]='USB buses cannot be enumerated.'
    [setpci]='PCI device identifiers cannot be reported.'
)

declare -r -a FIELDS=('identifier' 'parent' 'row_heading' 'serial' 'vendor_device_code' 'r_flag' 'resource_count' 'resource_unit' 'nominal_speed' 'goodput' 'driver' 'description')

declare -A usb_devices=() # Script-global associative array of USB device numbers to device paths
declare -A block_devices=() # Script-global associative array of block device names to their properties

declare -r -i max_numeric_format_precision="${options[max-precision]-2}"

join() {
    local -r IFS="${1}"
    shift
    echo "$*"
}

command_available() {
    local -r command_to_check="${1:?Command to check not specified}"
    command -v "$1" &> /dev/null
}

require_commands() {
    local missing_command
    local -a missing_commands=()
    for missing_command in "${REQUIRED_COMMANDS[@]}" 
    do
        if ! command_available "$missing_command"
        then
            missing_commands+=("$missing_command")
        fi
    done
    if ((${#missing_commands[@]} > 0))
    then
        >&2 echo -e "\e[1m\e[91mError:\e[0m missing required commands \e[1m$(join , "${missing_commands[@]}")\e[0m."
        exit 1
    fi
}

require_commands

noopify_missing_optional_commands() {
    local optional_command
    for optional_command in "${!OPTIONAL_COMMANDS[@]}"
    do
        if ! command_available "$optional_command"
        then
            >&2 echo -e "\e[1m\e[93mWarning:\e[0m missing optional command \e[1m$optional_command\e[0m. ${OPTIONAL_COMMANDS[$optional_command]}"
            eval "$optional_command() {
    :
}"
        fi
    done
}

noopify_missing_optional_commands

pluralize() {
    local -r term="$1"
    local -r count="$2"
    if [ -n "$count" ] && [ -n "$term" ]
    then
        if [ "$count" != "1" ]
        then
            echo "${term}s"
        else
            echo "$term"
        fi
    fi
}

list_subdirectories_by_natural_order() {
    local -r directory="${1:?Directory not supplied}"
    local -r name_pattern="${2-*}"
    local -r negative_name_pattern="${3-}"
    find -L "$directory/" -mindepth 1 -maxdepth 1 \( -name "$name_pattern" \! -name "$negative_name_pattern" \) -type d -print0 | sort -z -V
}

print_file_if_exists () {
    if [ -z "$2" ]
    then
        local -r file_path="${1:?File path not specified}"
        local -r format_string='%s'
    else
        local -r format_string="$1"
        local -r file_path="$2"
    fi
    [[ -r "$file_path" ]] && printf -- "$format_string" "$(< "$file_path")"
}

calc() {
    bc -l <<< "$*" | xargs printf -- "%.${max_numeric_format_precision}f" | sed -E 's/(^-?[[:digit:]]*)((\.[[:digit:]]*[1-9])|\.)0*$/\1\3/'
}

format_to_si() {
    local -r measure="${1:?Measure not specified}"
    local -r value="$2"
    local -i exponent
    local si_prefix
    if [ -n "$2" ]
    then
        while read -r si_prefix exponent
        do
            if (($(calc "$value>=10^$exponent")))
            then
                echo "$(calc "$value/10^$exponent") $si_prefix$measure"
                return
            fi
        done < <(for si_prefix in "${!SI_PREFIX_MAP[@]}"; do echo "$si_prefix ${SI_PREFIX_MAP[$si_prefix]}"; done | sort --reverse --general-numeric-sort --key=2)
        echo "$value $measure"
    fi
}

format_sector_count() {
    local -r -i bytes="$((${1:?Sector count not specified}*512))"
    format_to_si 'B' "$bytes"
}

format_usb_speed() {
    local -r usb_speed="$1"
    [ -n "$usb_speed" ] && format_to_si 'bps' "$(calc "10^${SI_PREFIX_MAP[M]}*$usb_speed")"
}

format_usb_goodput() {
    local -r usb_speed="${USB_SPEED_MAP[${1:?USB speed not specified}]}"
    [ -n "$usb_speed" ] && format_to_si 'bps' "$(calc "10^${SI_PREFIX_MAP[M]}*$usb_speed")"
}

format_sata_goodput() {
    local -r sata_speed="${SATA_SPEED_MAP[${1:?SATA speed not specified}]}"
    [ -n "$sata_speed" ] && format_to_si 'bps' "$(calc "10^${SI_PREFIX_MAP[G]}*$sata_speed")"
}

collect_row() {
    local -A values
    local -i index
    for ((index = 1; index < ${#FIELDS[@]} + 1; index++))
    do
        values[${FIELDS[$index-1]}]="${!index-}"
    done
    local -r -i root=$([ -z "${values[parent]}" ] && echo 1)
    local -r -i highlight=${!index:-0}
    local -r format="%s\t%s\t$(((root)) && printf '\e[1m\e[4m')$(((highlight)) && echo -en '\e[30m\e[103m')%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s$(((root || highlight)) && printf '\e[0m')\n"
    printf "$format" \
        "${values[identifier]}" \
        "${values[parent]}" \
        "${values[row_heading]}${values[serial]:+ (${values[serial]})}" \
        "${values[vendor_device_code]}" \
        "${values[r_flag]}" \
        "${values[resource_count]} $(pluralize "${values[resource_unit]}" "${values[resource_count]}")" \
        "${values[nominal_speed]}" \
        "${values[goodput]:+(${values[goodput]})}" \
        "${values[driver]}" \
        "${values[description]}"
}

enumerate_network_interfaces() {
    local -r parent="${1:?Parent not specified}"
    local -r directory="${2:?Directory to scan not specified}"
    local net_interface interface_name address connections speed goodput
    for net_interface in "$directory/net"/*
    do
        interface_name="${net_interface##*/}"
        address="$(! (("${options[no-unique-ids]-}")) \
                && xargs -a "$net_interface/address" \
                || :)"
        if [[ "$(< "$net_interface/operstate")" = 'up' ]]
        then
            connections=1
            if (("$(< "$net_interface/speed")"))
            then
                speed="$(calc "10^${SI_PREFIX_MAP[M]}*$(< "$net_interface/speed")")"
                goodput="$((("${options[show-goodput]-}")) \
                        && printf "$speed" \
                        || :)"
            else
                unset speed goodput
            fi
        else
            unset connections
        fi
        collect_row "$parent/net$interface_name" "$parent" "Network $interface_name" "$address" '' '' "${connections-}" 'connection' "$(format_to_si 'bps' "${speed-}")" "$(format_to_si 'bps' "${goodput-}")" ''
    done
}

build_block_device_map() {
    local block_device
    local block_device_properties
    while IFS= read -r -d $'\n' line
    do
        block_devices["${line%% *}"]="${line#* }"
    done < <(lsblk --nodeps --output NAME,MODEL,WWN,SERIAL,SIZE --noheadings --raw --bytes)
}

enumerate_nvme_interfaces() {
    local -r parent="${1:?Parent not specified}"
    local -r slot="${2:?PCI slot not specified}"
    local _ nvme_interface interface_name interface_number model serial namespaces namespace_name namespace_id namespace_unique_id namespace_size
    for nvme_interface in "$PCI_DEVICE_BASE_PATH/$slot/nvme"/nvme*
    do
        interface_name="${nvme_interface##*/}"
        interface_number="${interface_name##nvme}"
        model="$(! (("${options[no-descriptions]-}")) \
              && xargs -a "$nvme_interface/model" \
              || :)"
        serial="$(! (("${options[no-unique-ids]-}")) \
               && xargs -a "$nvme_interface/serial" \
               || :)"
        namespaces="$(find "$nvme_interface/" -name "${interface_name}n*" -maxdepth 1 -type d | wc -l)"
        collect_row "$parent/$interface_name" "$parent" "NVMe interface #$interface_number" "$serial" '' '' "$namespaces" 'namespace' '' '' '' "$model"
        for namespace in "$nvme_interface/${interface_name}n"*
        do
            namespace_name=${namespace##*/}
            namespace_id="$(< "$namespace/nsid")"
            if ! (("${options[no-unique-ids]-}")) && [ -n "${block_devices["$namespace_name"]-}" ]
            then
                IFS=' ' read -r _ namespace_unique_id _ namespace_size <<< "${block_devices["$namespace_name"]}"
            fi
            namespace_size="${namespace_size:-$(calc "$(< "$namespace/size")*512")}"
            collect_row "$parent/$namespace_name" "$parent/$interface_name" "Block device $namespace_name" "${namespace_unique_id-}" '' '' $(format_to_si 'B' "$namespace_size") '' '' '' ''
        done
    done
}

enumerate_storage_hosts() {
    local -r parent="${1:?Parent not specified}"
    local -r interface="${2:?storage interface path not specified}"
    local -r link_speed="${3-}"
    local -r goodput="$(! (("${options[no-unique-ids]-}")) \
                     && printf "${4-}" \
                     || :)"
    local _ host host_name target target_name scsi_device scsi_device_description scsi_device_serial block_device block_device_name block_device_size block_device_removable
    while IFS= read -r -d '' host
    do
        host_name=${host##*/}
        while IFS= read -r -d '' target
        do
            target_name=${target##*/}
            while IFS= read -r -d '' scsi_device
            do
                while IFS= read -d '' -r block_device
                do
                    block_device_name=${block_device##*/}
                    if ! (("${options[no-unique-ids]-}")) && [ -n "${block_devices["$block_device_name"]-}" ]
                    then
                        IFS=' ' read -r _ _ scsi_device_serial _ <<< "${block_devices["$block_device_name"]}"
                    fi
                    scsi_device_description="$(! (("${options[no-descriptions]-}")) \
                                            && paste -d ' ' "$scsi_device/vendor" "$scsi_device/model" | xargs \
                                            || :)"
                    block_device_size="$([[ -r "$block_device/size" ]] \
                                      && xargs -a "$block_device/size" \
                                      || printf 0)"
                    block_device_removable="$([[ -r "$block_device/removable" ]] \
                                           && (("$(xargs -a "$block_device/removable")")) \
                                           && echo '[R]' \
                                           || :)"
                    collect_row "$parent/$block_device_name" "$parent" "Block device $block_device_name" "${scsi_device_serial-}" '' "$block_device_removable" $(format_sector_count "$block_device_size") "$link_speed" "$goodput" '' "$scsi_device_description"
                done < <(list_subdirectories_by_natural_order "$scsi_device/block")
            done < <(list_subdirectories_by_natural_order "$target" "${target_name##*target}:*")
        done < <(list_subdirectories_by_natural_order "$host" 'target*:*:*')
    done < <(list_subdirectories_by_natural_order "$interface" 'host*')
}

enumerate_ata_interfaces() {
    local -r parent="${1:?Parent not specified}"
    local -r slot="${2:?PCI slot not specified}"
    local ata_interface ata_link link_speed goodput
    while IFS= read -r -d '' ata_interface
    do
        while IFS= read -r -d '' ata_link
        do
            if [[ -r "$ata_link/sata_spd" ]]
            then
                link_speed="$(< "$ata_link/sata_spd")"
                goodput="$((("${options[show-goodput]-}")) \
                        && [ "$link_speed" != '<unknown>' ] \
                        && format_sata_goodput "$link_speed" \
                        || :)"
            else
                unset link_speed goodput
            fi
        done < <(list_subdirectories_by_natural_order "$ata_interface"/link*/ata_link 'link*')
        enumerate_storage_hosts "$parent" "$ata_interface" "${link_speed-}" "${goodput-}"
    done < <(list_subdirectories_by_natural_order "$PCI_DEVICE_BASE_PATH/$slot" 'ata*')
}

build_usb_device_map() {
    local usb_device
    local -i usb_bus_number
    local -i usb_device_number
    while IFS= read -r -d '' usb_device
    do
        if [[ -e "$usb_device/busnum" ]] && [[ -e "$usb_device/devnum" ]]
        then
            usb_devices["$(< "$usb_device/busnum")-$(< "$usb_device/devnum")"]="$usb_device"
        fi
    done < <(list_subdirectories_by_natural_order "$USB_DEVICE_BASE_PATH" '*-*' '*-*:*')
}

enumerate_usb_buses() {
    local -r parent="${1:?Parent not specified}"
    local -r slot="${2:?PCI slot not specified}"
    local usb_bus usb_bus_number usb_bus_ports usb_bus_speed usb_bus_goodput usb_device usb_device_serial usb_device_interfaces usb_device_speed usb_device_goodput usb_device_description usb_device_interface usb_interface_number usb_interface_driver
    while IFS= read -r -d '' usb_bus && [ -n "$usb_bus" ]
    do
        usb_bus_number="$(< "$usb_bus/busnum")"
        usb_bus_ports="$(< "$usb_bus/maxchild")"
        usb_bus_speed="$(< "$usb_bus/speed")"
        usb_bus_goodput="$((("${options[show-goodput]-}")) \
                        && format_usb_goodput "$usb_bus_speed" \
                        || :)"
        collect_row "$parent/usb$usb_bus_number" "$parent" "USB bus #$usb_bus_number" '' '' '' "$usb_bus_ports" 'port' "$(format_usb_speed "$usb_bus_speed")" "$usb_bus_goodput" '' ''
        if command_available lsusb
        then
            while IFS=' ' read -r usb_device_number usb_device_id usb_device_description
            do
                usb_device="${usb_devices[$usb_bus_number-$usb_device_number]-}"
                if [ -n "$usb_device" ]
                then
                    usb_device_removable="$([[ -r "$usb_device/removable" ]] \
                                         && [ $(xargs -a "$usb_device/removable") = 'removable' ] \
                                         && echo '[R]' \
                                         || :)"
                    usb_device_serial="$(! (("${options[no-unique-ids]-}")) \
                                      && [[ -r "$usb_device/serial" ]] \
                                      && xargs -a "$usb_device/serial" \
                                      || :)"
                    usb_device_interfaces="$(< "$usb_device/bNumInterfaces")"
                    usb_device_speed="$(< "$usb_device/speed")"
                    usb_device_goodput="$((("${options[show-goodput]-}")) \
                                       && format_usb_goodput "$usb_device_speed" \
                                       || :)"
                    usb_device_description="$(! (("${options[no-descriptions]-}")) \
                                           && [[ -r "$usb_device/manufacturer" ]] \
                                           && [[ -r "$usb_device/product" ]] \
                                           && paste -d ' ' "$usb_device/manufacturer" "$usb_device/product" | xargs \
                                           || :)"
                else
                    unset usb_device_removable usb_device_serial usb_device_interfaces usb_device_speed usb_device_goodput
                fi
                collect_row "$parent/usb$usb_bus_number/$usb_device_number" "$parent/usb$usb_bus_number" "Device #$usb_device_number" "${usb_device_serial-}" "$usb_device_id" "${usb_device_removable-}" "${usb_device_interfaces-}" 'interface' "$(format_usb_speed "${usb_device_speed-}")" "${usb_device_goodput-}" '' "$(! (("${options[no-descriptions]-}")) && echo "${usb_device_description-}")"
                if [ -n "$usb_device" ]
                then
                    while IFS= read -r -d '' usb_interface
                    do
                        usb_interface_number="$(sed -E 's/^0*([0-9]+)$/\1/' "$usb_interface/bInterfaceNumber")"
                        if [[ -L "$usb_interface/driver" ]]
                        then
                            usb_interface_driver="$(readlink -f "$usb_interface/driver")"
                            usb_interface_driver="${usb_interface_driver##*/}"
                        else
                            unset usb_interface_driver
                        fi
                        collect_row "$parent/usb$usb_bus_number/$usb_device_number/$usb_interface_number" "$parent/usb$usb_bus_number/$usb_device_number" "Interface #$usb_interface_number" '' '' '' '' '' '' '' "${usb_interface_driver-}" ''
                        enumerate_storage_hosts "$parent/usb$usb_bus_number/$usb_device_number/$usb_interface_number" "$usb_interface"
                        enumerate_network_interfaces "$parent/usb$usb_bus_number/$usb_device_number/$usb_interface_number" "$usb_interface"
                    done < <(list_subdirectories_by_natural_order "$usb_device" "${usb_device##*/}:*")
                fi
            done < <(lsusb -s "$usb_bus_number:" | sort -V | sed -E 's/^Bus 0*[0-9]+ Device 0*([0-9]+): ID ([0-9a-f]{4}:[0-9a-f]{4}) (.*)$/\1 \2 \3/')
        fi
    done < <(list_subdirectories_by_natural_order "$PCI_DEVICE_BASE_PATH/$slot" 'usb*')
}

scan_pci_device() {
    local -r parent="${1:?IOMMU group number not specified}"
    local -r slot="${2:?PCI slot not specified}"
    local -r device="$PCI_DEVICE_BASE_PATH/$slot"
    local -A device_properties=()
    local device_property row_heading device_reset_flag device_link_width device_link_speed device_goodput device_description
    if (("${options[no-pci-bridges]-}")) && [[ "$(< "$device/class")" == "$PCI_BRIDGE_BASE_CLASS_CODE"* ]]
    then
        return
    fi
    while IFS= read -r device_property && [ -n "$device_property" ]
    do
        device_properties[${device_property%%:	*}]="${device_property#*:	}"
    done < <(lspci -Dkvmmnns $slot)
    if ! (("${options[no-unique-ids]-}")) && command_available setpci && 2> /dev/null 1>&2 setpci -f -s "$slot" ECAP_DSN.L
    then
        device_properties[DeviceSerialNumber]=$(setpci -f -s "$slot" ECAP_DSN\+08.L ECAP_DSN\+04.L | tr -d '\n')
    fi
    if (("${options[strip-pci-domain]-}"))
    then
        row_heading="Slot ${slot##????:}"
    else
        row_heading="Slot $slot"
    fi
    if [[ -f "$device/reset" ]]
    then
        device_reset_flag='[R]'
    fi
    if [[ -r "$device/current_link_speed" ]] && [[ -r "$device/current_link_width" ]] 
    then
        device_link_width="$(< "$device/current_link_width")"
        device_link_speed="$(< "$device/current_link_speed")"
        device_goodput="$((("${options[show-goodput]-}")) \
                       && [[ -n "${PCIE_SPEED_MAP[$device_link_speed]-}" ]] \
                       && format_to_si 'bps' $(calc "$device_link_width*10^${SI_PREFIX_MAP[G]}*${PCIE_SPEED_MAP[$device_link_speed]}") \
                       || :)"
    fi
    if ! (("${options[no-descriptions]-}"))
    then
        device_description="${device_properties[Vendor]:0:(-7)} ${device_properties[Device]:0:(-7)}"
    fi
    collect_row "$parent/$slot" "$parent" "$row_heading" "${device_properties[DeviceSerialNumber]-}" "${device_properties[Vendor]:(-5):(-1)}:${device_properties[Device]:(-5):(-1)}" "${device_reset_flag-}" "${device_link_width-}" 'lane' "${device_link_speed-}" "${device_goodput-}" "${device_properties[Driver]-}" "${device_description-}" $([ "${device_properties[Driver]-}" = 'vfio-pci' ] && echo 1)
    if ! (("${options[only-pci-devices]-}"))
    then
        enumerate_usb_buses "$parent/$slot" "$slot"
        enumerate_ata_interfaces "$parent/$slot" "$slot"
        enumerate_nvme_interfaces "$parent/$slot" "$slot"
        enumerate_network_interfaces "$parent/$slot" "$device"
    fi
}

enumerate_iommu_groups() {
    local pci_domains pci_bus group group_number number_of_devices plural_suffix device slot has_non_pci_bridge_slots
    local -a specific_iommu_groups
    if (("${options[strip-pci-domain]-}"))
    then
        local -A pci_domains=()
        for pci_bus in $PCI_DOMAIN_BUS_PATH_PATTERN
        do
            pci_domains=("${pci_bus:16:4}")
        done
        if ((${#pci_domains[@]} > 1))
        then
            >&2 printf '\e[1m\e[93mWarning:\e[0m multiple PCI domains found: \e[1m%s\e[0m\nThe \e[1m--strip-pci-domain\e[0m option will be ignored.\n' "${!pci_domains[@]}"
            unset 'options[strip-pci-domain]'
        fi
    fi
    if (("${options[no-pci-bridges]-}"))
    then
        local -A pci_bridge_slots=()
        for device in "$PCI_DEVICE_BASE_PATH"/*
        do
            if [[ "$(< "$device/class")" == "$PCI_BRIDGE_BASE_CLASS_CODE"* ]]
            then
                pci_bridge_slots[${device##*/}]=1
            fi
        done
    fi
    if [ -n "${options[iommu-groups]-}" ]
    then
        IFS=, read -r -a specific_iommu_groups <<< "${options[iommu-groups]}"
    fi
    while IFS= read -r -d '' group && [ -n "$group" ]
    do
        if (("${options[no-pci-bridges]-}"))
        then
            has_non_pci_bridge_slots=0
            for device in "$group/devices"/????:??:??.?
            do
                if ! (("${pci_bridge_slots[${device##*/}]-}"))
                then
                    has_non_pci_bridge_slots=1
                    break
                fi
            done
            if ! (("$has_non_pci_bridge_slots"))
            then
                continue
            fi
        fi
        group_number=${group##*/}
        if [ -z "${options[iommu-groups]-}" ] || [[ " ${specific_iommu_groups[*]} " =~ " $group_number " ]]
        then
            collect_row "$group_number" '' "IOMMU group #$group_number" '' '' '' '' '' '' '' '' ''
            for device in "$group/devices"/????:??:??.?
            do
                slot=${device##*/}
                scan_pci_device "$group_number" "$slot"
            done
        fi
    done < <(list_subdirectories_by_natural_order "$IOMMU_GROUPS_BASE_PATH")
}

print_headings() {
    printf "Row Identifier\t\tIdentifiers\tCode\t\tResources\tNominal Speed\tGoodput\tDriver\tDescription\n"
}

run() {
    if ! (("${options[only-pci-devices]-}"))
    then
        if ! (("${options[no-unique-ids]-}"))
        then
            build_block_device_map
        fi
        build_usb_device_map
    fi
    local -r table="$(! (("${options[no-headings]-}")) && print_headings; enumerate_iommu_groups)"
    local -A columns_to_hide=([1]=1 [2]=1)
    local -a additional_column_options=()
    if (("${options[no-resources]-}"))
    then
        columns_to_hide[6]=1
        columns_to_hide[7]=1
        columns_to_hide[8]=1
    fi
    if (("${options[show-goodput]-}"))
    then
        unset 'columns_to_hide[8]'
    else
        columns_to_hide[8]=1
    fi
    additional_column_options+=('--table-hide' "$(printf '%s,' "${!columns_to_hide[@]}")")
    if ! (("${options[no-wrap]-}"))
    then
        additional_column_options+=('--table-noextreme' '3,10')
        additional_column_options+=('--table-wrap' '10')
    fi
    column --separator $'\t' --table --tree-id 1 --tree-parent 2 --tree 3 --table-right 6,7,8 "${additional_column_options[@]}" <<< "$table"
}

run

