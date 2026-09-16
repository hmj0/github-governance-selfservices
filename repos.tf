locals {
  repos = yamldecode(file("${path.module}/repos.yaml"))["repositories"]
}

resource "github_repository" "this" {
  for_each    = local.repos
  name        = each.key
  description = each.value.description
  visibility  = each.value.visibility
  topics      = try(each.value.topics, [])
  auto_init   = true

  # Sans ce bloc, retirer simplement une entrée de repos.yaml suffirait à
  # faire supprimer le repo au prochain apply — aucune des permissions
  # GitHub (team_repository = push, pas admin) ne protège contre ce cas
  # précis, puisque la suppression passerait par Terraform, pas par l'UI.
  # Le rapport (Annexe I) promettait explicitement que ce ne soit pas
  # possible par simple retrait de ligne ; ce garde-fou tient cette promesse.
  lifecycle {
    prevent_destroy = true
  }
}

# Va chercher une team qui existe déjà (créée par Fondations) — ne crée jamais rien.
# Les teams sont nommées "team-<nom>" (voir teams.tf) alors que team_owner dans
# repos.yaml utilise le nom court ("dev"), pour matcher les allowed_values des
# custom properties. On reconstitue donc le slug ici.
# Si team_owner ne correspond à aucune team réelle, le plan échoue ici, proprement,
# avant même de tenter la création du repo.
data "github_team" "by_name" {
  for_each = toset(distinct([for r in local.repos : r.team_owner]))
  slug     = "team-${each.value}"
}

resource "github_team_repository" "this" {
  for_each   = local.repos
  team_id    = data.github_team.by_name[each.value.team_owner].id
  repository = github_repository.this[each.key].name
  permission = "push"

  # Même raisonnement que sur github_repository.this : sans ce bloc, un
  # simple retrait de ligne dans repos.yaml supprimerait l'attribution à la
  # team avant même que Terraform ne bloque sur le repo lui-même, laissant
  # un repo protégé mais orphelin de toute équipe.
  lifecycle {
    prevent_destroy = true
  }
}

# Pose les valeurs des custom properties obligatoires sur chaque repo créé.
# Le schéma (noms, valeurs autorisées) est défini une seule fois côté Fondations ;
# ici on ne fait que renseigner, pour CE repo, la valeur choisie dans repos.yaml.
locals {
  managed_properties = ["team_owner", "data_classification", "criticality"]

  # Aplatit repo × propriété en une seule map : "poc-service-api:team_owner" => {...}
  repo_properties = merge([
    for repo_name, repo in local.repos : {
      for prop in local.managed_properties :
      "${repo_name}:${prop}" => {
        repo  = repo_name
        name  = prop
        value = repo[prop]
      }
    }
  ]...)
}

resource "github_repository_custom_property" "this" {
  for_each = local.repo_properties

  repository     = github_repository.this[each.value.repo].name
  property_name  = each.value.name
  property_type  = "single_select"
  property_value = [each.value.value]

  # Même protection, pour la même raison : sans elle, les métadonnées d'un
  # repo pourraient disparaître même si le repo lui-même survit grâce à la
  # protection posée sur github_repository.this.
  lifecycle {
    prevent_destroy = true
  }
}

# Fichiers de gouvernance/hygiène propagés à chaque repo créé, lus depuis
# leur propre copie dans CE dépôt (self-services) — modifier une de ces
# copies et appliquer met à jour l'ensemble des repos gérés en une fois,
# sans toucher à repos.yaml. Un for_each combiné (repo × fichier) plutôt
# que trois ressources dupliquées : ajouter un futur 4e fichier ne demande
# qu'une ligne dans local.propagated_files, pas un nouveau bloc de code.
locals {
  propagated_files = {
    "pr-agent.yml"   = ".github/workflows/pr-agent.yml"
    "dependabot.yml" = ".github/dependabot.yml"
    "pin-actions.yml" = ".github/workflows/pin-actions.yml"
  }

  # Aplatit repo × fichier en une seule map : "poc-service-api:pr-agent.yml" => {...}
  repo_files = merge([
    for repo_name, repo in local.repos : {
      for file_key, file_path in local.propagated_files :
      "${repo_name}:${file_key}" => {
        repo = repo_name
        path = file_path
      }
    }
  ]...)
}

resource "github_repository_file" "propagated" {
  for_each = local.repo_files

  repository          = github_repository.this[each.value.repo].name
  branch              = "main"
  file                = each.value.path
  content             = file("${path.module}/${each.value.path}")
  commit_message      = "Ajout automatique des fichiers de gouvernance self-service"
  overwrite_on_create = true

  # Volontairement SANS lifecycle prevent_destroy — voir Annexe J.31 :
  # ces fichiers sont des conforts/garde-fous recréés à la prochaine
  # dérive s'ils disparaissent, pas des ressources de gouvernance
  # critiques comme le repo, l'accès d'équipe ou les custom properties.
}