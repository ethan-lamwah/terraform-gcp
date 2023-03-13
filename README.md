# terraform-gcp

Use Terraform to provision a GCP infrastructure that uses Log Sink to capture filtered logs and then publishes message to a Pub/Sub topic. Once a message is received by the topic, the topic will trigger a Cloud Function (2nd gen).

## terraform script

Initialize terraform:
`terraform init`

Preview and validate the terraform configuration:
`terraform plan`

Creat the resources by applying the configuration. When prompted, enter `yes`:
`terraform apply`

Clean up all the resources defined in the configuration file:
`terraform destroy`

## Preparing zipped function source code

1. Change to the directory that contains the Cloud Functions source code:

    ```sh
    cd functions/pubsub
    ```

2. Create a zip file cotaining the function source code that Terraform will upload to a Cloud Storage bucket:

    ```sh
    zip -r function-source.zip .
    ```

## Reference

[Terraform - google docunentation](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
[Set detination permissions - Log sink to Pub/Sub topic](https://cloud.google.com/logging/docs/export/configure_export_v2#dest-auth)