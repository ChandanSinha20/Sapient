provider "google" {
  project     = "internal-interview-candidates"
  region      = "us-west2"
}
# Main VPC
resource "google_compute_network" "chandan-vpc" {
  name                    = "chandan-vpc"
  auto_create_subnetworks = false
}
# Public Subnet
# https://www.terraform.io/docs/providers/google/r/compute_subnetwork.html
resource "google_compute_subnetwork" "chandan-public-subnet" {
  name          = "chandan-public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = "us-west2"
  network       = google_compute_network.chandan-vpc.id
}
# Private Subnet
# https://www.terraform.io/docs/providers/google/r/compute_subnetwork.html
resource "google_compute_subnetwork" "chandan-private-subnet" {
  name          = "chandan-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = "us-west2"
  network       = google_compute_network.chandan-vpc.id
}
# Cloud Router
# https://www.terraform.io/docs/providers/google/r/compute_router.html
resource "google_compute_router" "chandan-router" {
  name    = "chandan-router"
  network = google_compute_network.chandan-vpc.id
  bgp {
    asn            = 64514
    advertise_mode = "CUSTOM"
  }
}
# NAT Gateway
# https://www.terraform.io/docs/providers/google/r/compute_router_nat.html
resource "google_compute_router_nat" "chandan-nat" {
  name                               = "chandan-nat"
  router                             = google_compute_router.chandan-router.name
  region                             = google_compute_router.chandan-router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = "chandan-private-subnet"
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}