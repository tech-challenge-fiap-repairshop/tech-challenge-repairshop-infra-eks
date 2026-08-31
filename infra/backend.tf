terraform {
  backend "s3" {
    bucket  = "fiap-repairshop2"
    key     = "eks/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}
