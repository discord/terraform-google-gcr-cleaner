# Grant cleaner service account access to delete references in Google Container Registry
# for buckets with uniform_bucket_level_access = false
resource "google_storage_bucket_access_control" "this" {
  for_each = toset(local.google_storage_bucket_access_control)

  bucket = each.value
  role   = "WRITER"
  entity = "user-${google_service_account.cleaner.email}"
}

# Grant cleaner service account access to delete references in Google Container Registry
# for buckets with uniform_bucket_level_access = true
resource "google_storage_bucket_iam_member" "this" {
  for_each = toset(local.google_storage_bucket_iam_member)

  bucket = each.value
  role   = "roles/storage.legacyBucketWriter"
  member = "serviceAccount:${google_service_account.cleaner.email}"
}

# Add IAM policy binding to the Cloud Run service
resource "google_cloud_run_service_iam_binding" "this" {
  location = google_cloud_run_service.this.location
  project  = google_cloud_run_service.this.project
  service  = google_cloud_run_service.this.name
  role     = "roles/run.invoker"
  members = [
    "serviceAccount:${google_service_account.invoker.email}"
  ]
}

# Grant cleaner service account roles/browser role in order to query the registry.
# This is the most minimal permission.
resource "google_project_iam_member" "this" {
  project = google_cloud_run_service.this.project
  role    = "roles/browser"
  member  = "serviceAccount:${google_service_account.cleaner.email}"
}

# Grant cleaner service account a custom role to read the repository
# and delete container images.

resource "google_project_iam_custom_role" "gar-cleaner" {
  role_id     = "artifactregistry.cleaner"
  title       = "GAR Cleaner"
  description = "Allows cleaning up unused Docker image versions and tags from GAR."
  permissions = [
    // Basic read permissions
    "artifactregistry.dockerimages.get",
    "artifactregistry.dockerimages.list",
    "artifactregistry.locations.get",
    "artifactregistry.locations.list",
    "artifactregistry.repositories.downloadArtifacts",
    "artifactregistry.repositories.get",
    "artifactregistry.repositories.list",
    "artifactregistry.tags.get",
    "artifactregistry.tags.list",
    "artifactregistry.versions.get",
    "artifactregistry.versions.list",
    // Delete permissions
    "artifactregistry.repositories.deleteArtifacts",
    "artifactregistry.tags.delete",
    "artifactregistry.versions.delete",
  ]
}

resource "google_artifact_registry_repository_iam_member" "this" {
  for_each = {
    for repo in var.gar_repositories : "${repo.name}_${repo.project_id != null ? repo.project_id : local.google_project_id}_${repo.region}" => repo...
  }

  project    = each.value[0].project_id != null ? each.value[0].project_id : local.google_project_id
  location   = each.value[0].region
  repository = "projects/${each.value[0].project_id != null ? each.value[0].project_id : local.google_project_id}/locations/${each.value[0].region}/repositories/${each.value[0].registry_name}"
  role       = google_project_iam_custom_role.gar-cleaner.id
  member     = "serviceAccount:${google_service_account.cleaner.email}"

  provider = google-beta
}

# Allow the account that is running terraform permissions to act-as
# the service-account, required for deploying a CloudRun service
resource "google_service_account_iam_member" "tf_as_cleaner" {
  count = local.running_as_a_service_account ? 1 : 0

  service_account_id = google_service_account.cleaner.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_client_openid_userinfo.terraform.email}"
}

# Allow the account that is running terraform permissions to act-as
# the service-account, required for deploying a CloudScheduler service
resource "google_service_account_iam_member" "tf_as_invoker" {
  count = local.running_as_a_service_account ? 1 : 0

  service_account_id = google_service_account.invoker.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${data.google_client_openid_userinfo.terraform.email}"
}
