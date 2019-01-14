terraform {
  backend "gcs" {
    bucket  = "tf-state-dr"
    prefix  = "terraform/state"
  }
}
