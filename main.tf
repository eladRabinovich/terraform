// Configure the Google Cloud provider
provider "google" {
 //credentials = "${file("${var.credentials}")}"
 credentials = "${file("./creds/serviceaccount.json")}"
 project     = "${var.gcp_project}"
 region      = "${var.region}"
}

// Create VPC
resource "google_compute_network" "vpc" {
    name                    = "${var.name}"
    auto_create_subnetworks = "false"
}

// Create private key for future access
resource "tls_private_key" "instances_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

 // Create .pem file
resource "local_file" "key_pair" {
  content  = "${tls_private_key.instances_key.private_key_pem}"
  filename = "${var.key_name}.pem"
  provisioner "local-exec"{
    command = "chmod 400 ${local_file.key_pair.filename}"
  }
}

// Create subnets by count
resource "google_compute_subnetwork" "subnet" {
    count         = "${var.mongodb_number}"
    name          = "${var.name}-subnet-${count.index}"
    ip_cidr_range = "${cidrsubnet(var.subnet_cidr, 8, count.index * 10)}"
    network       = "${var.name}"
    depends_on    = ["google_compute_network.vpc"]
    region        = "${var.region}"
}

// VPC firewall configuration #1 ssh, icmp from the world - TO REMOVE ? 
resource "google_compute_firewall" "allow-icmp-ssh" {
  name          = "${var.name}-fw-allow-icmp-ssh"
  network       = "${google_compute_network.vpc.name}"
  target_tags   = ["mongo-s", "mongo-p"]
  source_ranges = ["0.0.0.0/0"]

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}

// VPC firewall configuration #2 allow mongo tcp 27017 between the nodes
resource "google_compute_firewall" "allow-mongo-27017" {
  name          = "${var.name}-fw-allow-mongo-27017"
  network       = "${google_compute_network.vpc.name}"
  target_tags   = ["mongodb-dr"]
  source_ranges = ["${var.subnet_cidr}"]
  
  allow {
    protocol = "tcp"
    ports    = ["27017"]
  }
}

// Get availabe zone in the region
data "google_compute_zones" "available" {
  project     = "${var.gcp_project}"
  region      = "${var.region}"
}

// Create compute instances 
resource "google_compute_instance" "mongodb-instance" {
  count        = "${var.mongodb_number}"
  depends_on   = ["google_compute_subnetwork.subnet", "tls_private_key.instances_key"]
  name         = "${count.index == 0 ? "dr-mongodb-p" : "dr-mongodb-s${count.index - 1}"}"
  machine_type = "${var.machine_type}"
  zone         = "${data.google_compute_zones.available.names[count.index]}"
  tags = ["mongodb-dr"]

  boot_disk {
    initialize_params {
      image = "centos-7"
    }
  }

  metadata {
    sshKeys = "${var.ssh_user}:${tls_private_key.instances_key.public_key_openssh}"
  }
 
  network_interface {
    subnetwork = "mongos-dr-vpc-subnet-${count.index}"
    access_config {
      // Ephemeral IP - leaving this block empty will generate a new external IP and assign it to the machine
      // will be removed
    }
  }
}

output "IPs" {
  value = "${join("-",google_compute_instance.mongodb-instance.*.network_interface.0.network_ip)}"
}