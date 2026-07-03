terraform {
  backend "s3" {
    bucket  = "ihsan-aws-live-streaming-tfstate"
    key     = "terraform-aws-mediaservices/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}