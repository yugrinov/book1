##########################################
# terraform variables
# Please customize based on customer needs
##########################################
variable "vsphere_user" {
  default = "greenplum@vsphere.local"
}
variable "vsphere_password" {
  default = "DeleteMe123!"
}
variable "vsphere_server" {
  default = "IP.of.the.vCenter"
}
variable "vsphere_datacenter" {
  default = "name of the data center"
}
variable "vsphere_compute_cluster" {
  default = "name of the compute cluster"
}
variable "vsphere_datastore" {
  default = "Name of vSAN datastore"
}

variable "vsphere_storage_policy" {
  description = "Enter the custom name for your storage policy defined during Setting Up vSphere Storage/Encryption"
  default = "vSAN Greenplum FTT1 RAID1 Stripe1 Thick No Encryption"
}
variable "vm_template_name" {
  description = "VM template with vmware-tools and Greenplum installed"
  default = "greenplum-db-template"
}
variable "greenplum_instance_id" {
  description = "A unique identifier for this Greenplum instance"
  default = 1
}

variable "resource_pool_name" {
  description= "The name of a dedicated resource pool for Greenplum VMs which will be created by Terraform"
  default = "greenplum"
}

variable "gp_virtual_external_network" {
  default = "gp-virtual-external"
}
variable "gp_virtual_internal_network" {
  default = "gp-virtual-internal"
}
variable "gp_virtual_etl_bar_network" {
  default = "gp-virtual-etl-bar"
}

# gp-virtual-external network settings
variable "gp_virtual_external_ipv4_prefix" {
  type = string
  description = "The leading octets for the routable IP range, e.g. '10.0.0.'"
  default = "10.0.0."
}
variable "gp_virtual_external_ipv4_netmask" {
  description = "Netmask bitcount, e.g. 24"
  default = 24
}
variable "master_gp_virtual_external_ipv4_offset" {
  description = "The starting IP of the routable IP range"
  default = 10
}
variable "gp_virtual_external_gateway" {
  description = "Gateway for the gp-virtual-external network, e.g. 10.0.0.1"
  default = "10.0.0.1"
}
variable "dns_servers" {
  type = list(string)
  description = "The DNS servers for the routable network, e.g. 8.8.8.8"
  default = ["8.8.8.8"]
}

# gp-virtual-internal network settings
variable "gp_virtual_internal_ipv4_netmask" {
  description = "Netmask bitcount, e.g. 24"
  default = 24
}
variable "master_gp_virtual_internal_ipv4_offset" {
  description = "The starting IP of the master VM in gp-virtual-internal"
  default = 250
}
variable "segment_gp_virtual_internal_ipv4_offset" {
  description = "The starting IP of the segment VM in gp-virtual-internal"
  default = 2
}

# gp-virtual-etl-bar network settings
variable "gp_virtual_etl_bar_ipv4_prefix" {
  type = string
  description = "The leading octets for the data backup (doesn't have to be routable) network IP range, e.g. '192.168.2.'; make sure its not conflicting with the Internal Network IP Prefix you chose for the Internal Network."
  default = "192.168.2."
}
variable "gp_virtual_etl_bar_ipv4_netmask" {
  description = "Netmask bitcount, e.g. 24"
  default = 24
}
variable "master_gp_virtual_etl_bar_ipv4_offset" {
  description = "The starting IP of the master VM in gp-virtual-etl-bar"
  default = 250
}
variable "segment_gp_virtual_etl_bar_ipv4_offset" {
  description = "The starting IP of the segment VM in gp-virtual-etl-bar"
  default = 2
}

######################
# terraform scripts
# PLEASE DO NOT CHANGE
######################
provider "vsphere" {
  user           = var.vsphere_user
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server

  # If you have a self-signed cert
  allow_unverified_ssl = true
}

# all of these things need to be known for a deploy to work
data "vsphere_datacenter" "dc" {
  name          = var.vsphere_datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "gp_virtual_external_network" {
  name          = var.gp_virtual_external_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "gp_virtual_internal_network" {
  name          = var.gp_virtual_internal_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# vSphere distributed port group for ETL, backup and restore traffic
data "vsphere_network" "gp_virtual_etl_bar_network" {
  name          = var.gp_virtual_etl_bar_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "compute_cluster" {
  name          = var.vsphere_compute_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_storage_policy" "policy" {
  name = var.vsphere_storage_policy
}

# this points at the template created by the image folder
data "vsphere_virtual_machine" "template" {
  name          = var.vm_template_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

locals {
  internal_ip_prefix = "${data.vsphere_virtual_machine.template.vapp[0].properties["guestinfo.internal_ip_prefix"]}."
  segment_count = "${data.vsphere_virtual_machine.template.vapp[0].properties["guestinfo.segment_count"]}."
  memory = data.vsphere_virtual_machine.template.memory
  memory_reservation = data.vsphere_virtual_machine.template.memory / 2
  num_cpus = data.vsphere_virtual_machine.template.num_cpus
  root_disk_size_in_gb = data.vsphere_virtual_machine.template.disks[0].size
  data_disk_size_in_gb = data.vsphere_virtual_machine.template.disks[1].size
}
# end

resource "vsphere_resource_pool" "pool" {
  name                    = "${var.resource_pool_name}-${var.greenplum_instance_id}"
  parent_resource_pool_id = data.vsphere_compute_cluster.compute_cluster.resource_pool_id
}

resource "vsphere_virtual_machine" "segment_hosts" {
  count = local.segment_count
  name = format("gp-%d-sdw-%0.3d", var.greenplum_instance_id, count.index + 1)
  resource_pool_id = vsphere_resource_pool.pool.id
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout = 0
  guest_id = data.vsphere_virtual_machine.template.guest_id
  datastore_id = data.vsphere_datastore.datastore.id
  storage_policy_id = data.vsphere_storage_policy.policy.id
  scsi_controller_count = 2

  memory = local.memory
  memory_reservation = local.memory_reservation
  num_cpus = local.num_cpus # half of a host the cpus rounded down.
  cpu_share_level = "normal"
  memory_share_level = "normal"

  network_interface {
    network_id = data.vsphere_network.gp_virtual_internal_network.id
  }

  network_interface {
    network_id = data.vsphere_network.gp_virtual_etl_bar_network.id
  }

  swap_placement_policy = "vmDirectory"
  enable_disk_uuid = "true"
  disk {
    label = "disk0"
    size  = local.root_disk_size_in_gb
    unit_number = 0
    datastore_id = data.vsphere_datastore.datastore.id
    storage_policy_id = data.vsphere_storage_policy.policy.id
  }

  disk {
    label = "disk1"
    size  = local.data_disk_size_in_gb
    unit_number = 1
    datastore_id = data.vsphere_datastore.datastore.id
    storage_policy_id = data.vsphere_storage_policy.policy.id
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = "sdw${count.index + 1}"
        domain    = "local"
      }

      network_interface {
        ipv4_address = "${local.internal_ip_prefix}${count.index + var.segment_gp_virtual_internal_ipv4_offset}"
        ipv4_netmask = var.gp_virtual_internal_ipv4_netmask
      }

      network_interface {
        ipv4_address = "${var.gp_virtual_etl_bar_ipv4_prefix}${count.index + var.segment_gp_virtual_etl_bar_ipv4_offset}"
        ipv4_netmask = var.gp_virtual_etl_bar_ipv4_netmask
      }
    }
  }

  vapp {
    properties = data.vsphere_virtual_machine.template.vapp[0].properties
  }
}

resource "vsphere_virtual_machine" "master_hosts" {
  count = 2
  name = count.index == 0 ? format("gp-%d-mdw", var.greenplum_instance_id) : count.index == 1 ? format("gp-%d-smdw", var.greenplum_instance_id) : format("gp-%d-smdw-%d", var.greenplum_instance_id, count.index)
  resource_pool_id = vsphere_resource_pool.pool.id
  wait_for_guest_net_routable = false
  wait_for_guest_net_timeout = 0
  guest_id = data.vsphere_virtual_machine.template.guest_id
  datastore_id = data.vsphere_datastore.datastore.id
  storage_policy_id = data.vsphere_storage_policy.policy.id

  memory = local.memory
  memory_reservation = local.memory_reservation
  num_cpus = local.num_cpus
  cpu_share_level = "normal"
  memory_share_level = "normal"

  network_interface {
    network_id = data.vsphere_network.gp_virtual_internal_network.id
  }

  network_interface {
    network_id = data.vsphere_network.gp_virtual_etl_bar_network.id
  }

  network_interface {
    network_id = data.vsphere_network.gp_virtual_external_network.id
  }

  swap_placement_policy = "vmDirectory"
  enable_disk_uuid = "true"

  disk {
    label = "disk0"
    size  = local.root_disk_size_in_gb
    unit_number = 0
    datastore_id = data.vsphere_datastore.datastore.id
    storage_policy_id = data.vsphere_storage_policy.policy.id
  }

  disk {
    label = "disk1"
    size  = local.data_disk_size_in_gb
    unit_number = 1
    datastore_id = data.vsphere_datastore.datastore.id
    storage_policy_id = data.vsphere_storage_policy.policy.id
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id
    customize {
      linux_options {
        # master is always the first
        # standby master is always the second
        host_name = count.index == 0 ? format("mdw") : format("smdw")
        domain    = "local"
      }

      network_interface {
        ipv4_address = "${local.internal_ip_prefix}${count.index + var.master_gp_virtual_internal_ipv4_offset}"
        ipv4_netmask = var.gp_virtual_internal_ipv4_netmask
      }

      network_interface {
        ipv4_address = "${var.gp_virtual_etl_bar_ipv4_prefix}${count.index + var.master_gp_virtual_etl_bar_ipv4_offset}"
        ipv4_netmask = var.gp_virtual_etl_bar_ipv4_netmask
      }

      network_interface {
        ipv4_address = "${var.gp_virtual_external_ipv4_prefix}${count.index + var.master_gp_virtual_external_ipv4_offset}"
        ipv4_netmask = var.gp_virtual_external_ipv4_netmask
      }

      ipv4_gateway = var.gp_virtual_external_gateway
      dns_server_list = var.dns_servers
    }
  }

  vapp {
    properties = data.vsphere_virtual_machine.template.vapp[0].properties
  }
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "master_vm_anti_affinity_rule" {
    count               = 1
    enabled             = true
    mandatory           = true
    compute_cluster_id  = data.vsphere_compute_cluster.compute_cluster.id
    name                = format("master-vm-anti-affinity-rule")
    virtual_machine_ids = toset(vsphere_virtual_machine.master_hosts.*.id)
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "segment_vm_anti_affinity_rule" {
    count               = local.segment_count / 2
    enabled             = true
    mandatory           = true
    compute_cluster_id  = data.vsphere_compute_cluster.compute_cluster.id
    name                = format("segment-vm-anti-affinity-rule-sdw%0.3d-sdw%0.3d", count.index*2+1, count.index*2+2)
    virtual_machine_ids = [
        element(vsphere_virtual_machine.segment_hosts.*.id, count.index*2),
        element(vsphere_virtual_machine.segment_hosts.*.id, count.index*2+1),
    ]
}
