terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version    = ">= 4.34.0"
    }
  }
}

locals {
  project  = "datawarehouse-transform-tf"
  region = "us-central1"
}

provider "google" {
  project = local.project
  region = local.region
}

resource "random_id" "bucket_prefix" {
  byte_length = 8
}

resource "google_service_account" "account" {
  account_id   = "gcf-sa"
  display_name = "Test Service Account"
}

resource "google_pubsub_topic" "topic" {
  name = "functions2-topic"
}

resource "google_storage_bucket" "bucket" {
  name                        = "${random_id.bucket_prefix.hex}-gcf-source"
  location                    = "US"
  uniform_bucket_level_access = true
}

resource "google_storage_bucket_object" "object" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = "./pubsub/function-source.zip"
}

resource "google_cloudfunctions2_function" "function" {
  name        = "function-tf"
  location    = local.region
  description = "provision using tf"

  build_config {
    runtime     = "python39"
    entry_point = "subscribe"
    environment_variables = {
      BUILD_CONFIG_TEST = "build_test"
    }
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    max_instance_count = 3
    min_instance_count = 1
    available_memory   = "256M"
    timeout_seconds    = 60
    environment_variables = {
      SERVICE_CONFIG_TEST = "config_test"
    }
    ingress_settings = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email = google_service_account.account.email    
  }

  event_trigger {
    trigger_region = local.region
    event_type = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic = google_pubsub_topic.topic.id
    retry_policy = "RETRY_POLICY_RETRY"
  }
}
