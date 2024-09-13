variable "location" {
  type    = string
}
variable "github_group" {
  type    = string
}
variable "github_repo" {
  type    = string
}

locals {

  workload_id_pool_name = "github-pool"

  env_project_number_map = {
    dev = "XXXXXX"
    sta = "XXXXXX"
    prd = "XXXXXX"

  }

  project_map = {
    for env in ["dev", "sta", "prd"] :
    env => {
      number             = lookup(local.env_project_number_map, env)
      name               = "prj-${env}-xxxx"
      tf_service_account = "prj-${env}-xxxx-sac-terraform@prj-${env}-xxxx.iam.gserviceaccount.com"

    }

  }

}

resource "google_service_account" "github-sa" {
  for_each   = local.project_map
  account_id = "github-actions"
  project    = lookup(each.value, "name")
}

resource "google_iam_workload_identity_pool" "gha-pool" {
  for_each                  = local.project_map
  project                   = google_service_account.github-sa[each.key].project
  workload_identity_pool_id = local.workload_id_pool_name
  display_name              = "Github Actions Pool - Terraform"
  description               = "Identity pool for automated test created with terraform"
  disabled                  = false

}

resource "google_iam_workload_identity_pool_provider" "gha-provider" {
  for_each                           = local.project_map
  project                            = google_iam_workload_identity_pool.gha-pool[each.key].project
  workload_identity_pool_id          = google_iam_workload_identity_pool.gha-pool[each.key].workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  attribute_mapping                  = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"

  }
  attribute_condition = "assertion.repository_owner=='${var.github_group}'"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_binding" "admin-account-iam" {
  for_each           = local.project_map
  depends_on         = [
    google_iam_workload_identity_pool.gha-pool, google_iam_workload_identity_pool_provider.gha-provider
  ]
  service_account_id = google_service_account.github-sa[each.key].id
  role               = "roles/iam.workloadIdentityUser"
  members            = [
    "principalSet://iam.googleapis.com/projects/${lookup(each.value, "number")}/locations/global/workloadIdentityPools/${local.workload_id_pool_name}/attribute.repository/${var.github_group}/${var.github_repo}"
  ]
}

resource "google_project_iam_member" "storage-editor" {
  for_each = local.project_map
  member   = "serviceAccount:${google_service_account.github-sa[each.key].email}"
  project  = lookup(each.value, "name")
  role     = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "storage-editor-tf" {
  for_each = local.project_map
  member   = "serviceAccount:${lookup(each.value, "tf_service_account")}"
  project  = lookup(each.value, "name")
  role     = "roles/storage.objectAdmin"
}

resource "google_project_iam_member" "cloud-build-sa" {
  for_each = local.project_map
  member   = "serviceAccount:${google_service_account.github-sa[each.key].email}"
  project  = google_service_account.github-sa[each.key].project
  role     = "roles/cloudbuild.serviceAgent"
}

resource "google_service_account_iam_member" "tf-sa-impersonation" {
  for_each           = local.project_map
  member             = "serviceAccount:${google_service_account.github-sa[each.key].email}"
  role               = "roles/iam.serviceAccountUser"
  service_account_id = "projects/${google_service_account.github-sa[each.key].project}/serviceAccounts/${lookup(each.value, "tf_service_account")}"
}
