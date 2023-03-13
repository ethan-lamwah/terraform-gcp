terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 4.34.0"
    }
  }
}

locals {
  project = "datawarehouse-transform-tf" # Google Cloud Platform Project ID
  region  = "us-central1"
}

provider "google" {
  project = local.project
  region  = local.region
}

# Create Storage bucket for hosting zipped cloud function source code
resource "google_storage_bucket" "bucket" {
  name                        = "${local.project}-gcf-source" # Every bucket name must be globally unique
  location                    = "US"
  uniform_bucket_level_access = true
}

# Push zipped function source code to bucket
resource "google_storage_bucket_object" "object" {
  name   = "function-source.zip"
  bucket = google_storage_bucket.bucket.name
  source = "./pubsub/function-source.zip" # Add path to the zipped function source code
}

# Create Pub/Sub Topic
resource "google_pubsub_topic" "topic" {
  name = "functions2-topic"
}

# Create Log Sink
resource "google_logging_project_sink" "log-sink" {
  name = "pubsub-instance-sink"
  description = "Publish logs message to topic"
  destination = "pubsub.googleapis.com/${google_pubsub_topic.topic.id}"
  filter = "resource.type=\"bigquery_resource\" AND protoPayload.methodName=\"jobservice.getqueryresults\" AND protoPayload.serviceData.jobGetQueryResultsResponse.job.jobConfiguration.query.query=\"SELECT current_timestamp();\" "
  unique_writer_identity = true
}

# Grant the sink's writer identity the Pub/Sub publisher role to a specified topic.
resource "google_pubsub_topic_iam_member" "log-writer" {
  project = local.project
  topic = google_pubsub_topic.topic.name
  role = "roles/pubsub.publisher"
  member = google_logging_project_sink.log-sink.writer_identity
}

# Create Service Account
resource "google_service_account" "account" {
  account_id   = "gcf-sa"
  display_name = "Test Service Account"
}

# Permissions on the service account used by the function and Eventarc trigger
resource "google_project_iam_member" "invoking" {
  project = local.project
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.account.email}"
  depends_on = [
    google_service_account.account
  ]
}

resource "google_project_iam_member" "event-receiving" {
  project = local.project
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.account.email}"
  depends_on = [google_project_iam_member.invoking]
}

# Additional roles here...

# Create Cloud Function 2nd gen
resource "google_cloudfunctions2_function" "function" {
  depends_on = [
    google_service_account.account,
    google_project_iam_member.event-receiving
  ]
  name        = "function-tf"
  location    = local.region
  description = "provision by terraform"

  build_config {
    runtime     = "python39"
    entry_point = "subscribe" # Set the entry point 
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
    ingress_settings               = "ALLOW_INTERNAL_ONLY"
    all_traffic_on_latest_revision = true
    service_account_email          = google_service_account.account.email
  }

  event_trigger {
    trigger_region        = local.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.topic.id
    retry_policy          = "RETRY_POLICY_RETRY"
    service_account_email = google_service_account.account.email
  }
}
