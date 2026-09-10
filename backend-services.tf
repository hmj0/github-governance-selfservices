terraform {
  cloud {
    # Même principe que Fondations : "organization" omis, lu depuis
    # TF_CLOUD_ORGANIZATION à l'exécution.
    workspaces {
      name = "github-governance-selfservice"
    }
  }
}
