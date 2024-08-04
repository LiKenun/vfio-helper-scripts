# VFIO Helper Scripts

Are you getting your hands dirty with virtualization on a Linux host? This collection of scripts is for tinkerers of PCI device passthrough with VFIO.

As things currently stand, there is just one script: `enum_iommu_devices.sh`. 😿

But there’s more the pipelines. They just need some cleaning up. 😉

## Environment

These scripts have been tested primarily in Ubuntu 23.04+, although I will be doing more work on a Proxmox host soon. The Linux host running this script is expected to support the following commands:

* `bc`
* `column`
* `lspci`

The following commands are optional:

* `lsblk` for getting block device properties
* `lsusb` for enumerating USB devices on a USB bus
* `setpci` for getting PCI device identifiers

## Usage

`enum_iommu_devices.sh [-h | --help | [-i | --iommu-groups I] [--max-precision D] [-m | --minimal] [--no-descriptions] [--no-headings] [--no-pci-bridges] [--no-resources] [--no-unique-ids] [--no-wrap] [--only-pci-devices] [--show-goodput] [--strip-pci-domain]]`

### Arguments

    -h, --help              Display the script’s usage text.
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

The defaults work well for high-resolution displays. If your horizontal screen real estate is limited, you may want to avoid running the script with the defaults. Specify `--minimal` or some combination of `--no-unique-ids`, `--strip-pci-domain`, `--no-resources`, or `--no-descriptions`.

### Example Output

```
$ enum_iommu_devices.sh --max-precision 1 --no-pci-bridges --no-unique-ids --strip-pci-domain
Identifiers                 Code                Resources  Nominal Speed  Driver         Description                                                                
IOMMU group #0                                                                                                                                                      
└─Slot 00:02.0              8086:46a6  [R]        0 lanes        Unknown  i915           Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]                      
IOMMU group #3                                                                                                                                                      
└─Slot 00:08.0              8086:464f  [R]                                               Intel Corporation 12th Gen Core Processor Gaussian & Neural Accelerator    
IOMMU group #4                                                                                                                                                      
└─Slot 00:0a.0              8086:467d             0 lanes        Unknown  intel_vsec     Intel Corporation Platform Monitoring Technology                           
IOMMU group #5                                                                                                                                                      
├─Slot 00:14.0              8086:51ed                                     xhci_hcd       Intel Corporation Alder Lake PCH USB 3.2 xHCI Host Controller              
│ ├─USB bus #1                                   12 ports       480 Mbps                                                                                            
│ │ ├─Device #1             1d6b:0002                                                    Linux Foundation 2.0 root hub                                              
│ │ ├─Device #2             05e3:0610  [R]   1 interfaces       480 Mbps                 GenesysLogic USB2.0 Hub                                                    
│ │ │ └─Interface #0                                                      hub                                                                                       
│ │ ├─Device #3             8087:0033        2 interfaces        12 Mbps                                                                                            
│ │ │ ├─Interface #0                                                      btusb                                                                                     
│ │ │ └─Interface #1                                                      btusb                                                                                     
│ │ ├─Device #4             046d:c52b        3 interfaces        12 Mbps                 Logitech USB Receiver                                                      
│ │ │ ├─Interface #0                                                      usbhid                                                                                    
│ │ │ ├─Interface #1                                                      usbhid                                                                                    
│ │ │ └─Interface #2                                                      usbhid                                                                                    
│ │ ├─Device #14            0781:a7c1  [R]   1 interfaces       480 Mbps                 SanDisk SDDR-113                                                           
│ │ │ └─Interface #0                                                      usb-storage                                                                               
│ │ │   └─Block device sda             [R]      128.1 GBs                                SanDisk SDDR-113                                                           
│ │ ├─Device #15            11b0:3307        1 interfaces       480 Mbps                 Kingston UHSII uSD Reader                                                  
│ │ │ └─Interface #0                                                      usb-storage                                                                               
│ │ │   └─Block device sdb             [R]       31.3 GBs                                Kingston UHSII uSD Reader                                                  
│ │ └─Device #16            090c:1000        1 interfaces       480 Mbps                 Samsung Flash Drive FIT                                                    
│ │   └─Interface #0                                                      usb-storage                                                                               
│ │     └─Block device sdc             [R]       32.1 GBs                                Samsung Flash Drive FIT                                                    
│ └─USB bus #2                                    4 ports        10 Gbps                                                                                            
│   └─Device #1             1d6b:0003                                                    Linux Foundation 3.0 root hub                                              
└─Slot 00:14.2              8086:51ef                                                    Intel Corporation Alder Lake PCH Shared SRAM                               
IOMMU group #6                                                                                                                                                      
└─Slot 00:14.3              8086:51f0  [R]        0 lanes        Unknown  iwlwifi        Intel Corporation Alder Lake-P PCH CNVi WiFi                               
  └─Network wlo1                             1 connection                                                                                                           
IOMMU group #7                                                                                                                                                      
├─Slot 00:15.0              8086:51e8                                     intel-lpss     Intel Corporation Alder Lake PCH Serial IO I2C Controller #0               
└─Slot 00:15.1              8086:51e9                                     intel-lpss     Intel Corporation Alder Lake PCH Serial IO I2C Controller #1               
IOMMU group #8                                                                                                                                                      
└─Slot 00:16.0              8086:51e0                                     mei_me         Intel Corporation Alder Lake PCH HECI Controller                           
IOMMU group #9                                                                                                                                                      
└─Slot 00:17.0              8086:51d3                                     ahci           Intel Corporation Alder Lake-P SATA AHCI Controller                        
IOMMU group #12                                                                                                                                                     
├─Slot 00:1f.3              8086:51c8                                     snd_hda_intel  Intel Corporation Alder Lake PCH-P High Definition Audio Controller        
├─Slot 00:1f.4              8086:51a3                                     i801_smbus     Intel Corporation Alder Lake PCH-P SMBus Host Controller                   
└─Slot 00:1f.5              8086:51a4                                     intel-spi      Intel Corporation Alder Lake-P PCH SPI Controller                          
IOMMU group #13                                                                                                                                                     
└─Slot 01:00.0              144d:a808  [R]        4 lanes  8.0 GT/s PCIe  nvme           Samsung Electronics Co Ltd NVMe SSD Controller SM981/PM981/PM983           
  └─NVMe interface #0                         1 namespace                                SAMSUNG MZVLB512HBJQ-000H1                                                 
    └─Block device nvme0n1                      512.1 GBs                                                                                                           
IOMMU group #14                                                                                                                                                     
└─Slot 02:00.0              8086:15f3  [R]         1 lane  5.0 GT/s PCIe  igc            Intel Corporation Ethernet Controller I225-V                               
  └─Network enp2s0                                                                                                                                                  
IOMMU group #15                                                                                                                                                     
└─Slot 03:00.0              8086:2522  [R]         1 lane  8.0 GT/s PCIe  nvme           Intel Corporation NVMe Optane Memory Series                                
  └─NVMe interface #1                         1 namespace                                INTEL MEMPEI1J016GAL                                                       
    └─Block device nvme1n1                       14.4 GBs
```

With the arguments used, we’ve elected to show computed figures (the block device sizes in this example) with a maximum of one digit after the decimal point. PCI bridges are eliminated from the output. Unique identifiers are not shown. And the `0000:` PCI domain is stripped from the slot specification because there’s only one so it makes no difference.

## License

These scripts are [MIT licensed](https://github.com/LiKenun/vfio-helper-scripts/blob/main/LICENSE).
