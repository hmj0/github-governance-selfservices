# github-governance-selfservice

Dépôt de création de dépôts en libre-service. Chaque équipe déclare ses
besoins dans `repos.yaml` ; ce dépôt matérialise chaque entrée en un vrai
dépôt GitHub, avec son attribution d'équipe et ses custom properties.
C'est la **Couche 2** de l'architecture décrite dans le rapport de
conception — changements fréquents, revue légère (1 approbation).

Le dépôt frère `github-governance-foundations` constitue la Couche 1 : teams, rulesets et réglages généraux, dont ce
dépôt dépend mais qu'il ne modifie jamais.

---

## 1. Vue d'ensemble du fonctionnement

```
PR modifiant repos.yaml
        │
        ▼
Job "plan" (GitHub Actions) ──► commente le plan Terraform sur la PR
        │                        + mentionne automatiquement la/les
        │                          équipe(s) concernée(s) par ce diff
        ▼
1 approbation requise (ruleset général, hérité de Fondations)
        │
        ▼
Merge sur main
        │
        ▼
Job "apply" (GitHub Actions) ──► terraform apply automatique
```

Même principe de state que Fondations : **HCP Terraform, mode Local** — stockage et verrouillage seulement, l'exécution reste sur GitHub
Actions.

---

## 2. Prérequis

Identiques à `github-governance-foundations` §2 — compte HCP Terraform
avec accès à la même organisation HCP, droits Owner/Admin sur
l'organisation GitHub cible le temps de la mise en place initiale.

**Prérequis supplémentaire, propre à ce dépôt** : le premier `apply` de `github-governance-foundations` doit déjà avoir eu lieu — ce dépôt lit
les teams (`data.github_team.by_name`) qui n'existent qu'une fois
Fondations appliqué.

---

## 3. Mise en place initiale (une seule fois, par organisation)

### 3.1 — Créer le GitHub App dédié

Sur `github.com/organizations/<TON_ORG>/settings/apps/new` — **un App
distinct de celui de Fondations** (jamais de compte de service partagé
entre les deux couches) :

| Champ            | Valeur                                                               |
| ---------------- | -------------------------------------------------------------------- |
| GitHub App name  | `selfservice-governance-bot` (ou équivalent, unique sur tout GitHub) |
| Homepage URL     | L'URL de l'organisation suffit                                       |
| Webhook → Active | **Décoché**                                                          |

**Permissions à cocher — Repository permissions :**

| Permission        | Niveau         |
| ----------------- | -------------- |
| Administration    | Read and write |
| Custom properties | Read and write |

> Aucune Organization permission n'est nécessaire ici — ce dépôt ne lit
> les teams qu'en lecture seule (`data` source), jamais en écriture.

**Un point d'attention spécifique à ce dépôt** : même une fois les
permissions correctement cochées, l'écriture des custom properties
échoue tant que leur définition, côté Fondations
(`custom_properties.tf`), n'a pas `values_editable_by = "org_and_repo_actors"`. Vérifier ce réglage en premier si un `403` apparaît sur `github_repository_custom_property`.

Une fois créé : mêmes 3 étapes qu'en Fondations §3.1 (App ID, clé
privée, installation sur **All repositories**).

### 3.2 — Créer le workspace HCP Terraform

Même organisation HCP que Fondations, nouveau workspace :

1. **New workspace → CLI-Driven Workflow**
2. Nom exact : `github-governance-selfservice`
3. **Execution Mode → Local (custom)**
4. Un token d'API peut être réutilisé (celui généré pour Fondations
   fonctionne aussi bien, HCP Terraform ne les scope pas par workspace
   par défaut)

### 3.3 — Poser les Secrets et Variables GitHub Actions

Sur ce dépôt → **Settings → Secrets and variables → Actions**.

**Onglet Secrets :**

| Nom                   | Valeur                                                            |
| --------------------- | ----------------------------------------------------------------- |
| `APP_ID`              | L'App ID noté en 3.1 (celui de CE dépôt, pas celui de Fondations) |
| `APP_PRIVATE_KEY`     | Contenu intégral du `.pem`                                        |
| `HCP_TERRAFORM_TOKEN` | Le token HCP (réutilisable depuis Fondations)                     |

**Onglet Variables :**

| Nom       | Valeur                                  |
| --------- | --------------------------------------- |
| `GH_ORG`  | Même slug d'organisation que Fondations |
| `HCP_ORG` | Même organisation HCP que Fondations    |

---

## 4. Le tout premier apply

Contrairement à Fondations, aucune contrainte de revue ne bloque ce
dépôt dès sa création (le ruleset général vient de Fondations, déjà
actif). Une PR normale fonctionne donc dès le début — mais pour un tout
premier test rapide, un apply local reste possible, avec un PAT dédié
(distinct de celui de Fondations, ou le même — les scopes se recoupent) :

| Scope à cocher | Pourquoi                                                                                                                     |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `repo`         | Création des dépôts, attribution aux teams, écriture des custom properties                                                   |
| `read:org`     | Lecture des teams (`data "github_team"`) — en lecture seule, `admin:org` n'est pas nécessaire ici contrairement à Fondations |

```bash
git clone https://github.com/<TON_ORG>/github-governance-selfservice.git
cd github-governance-selfservice

cp terraform.tfvars.example terraform.tfvars
# édite terraform.tfvars : github_org

export GITHUB_TOKEN="un_PAT_admin_ou_le_token_du_GitHub_App"
export TF_TOKEN_app_terraform_io="le_token_HCP"
export TF_CLOUD_ORGANIZATION="ton_organisation_HCP"

terraform init
terraform plan
terraform apply
```

---

## 5. Fonctionnement courant

Déclarer un nouveau dépôt : éditer `repos.yaml`.

```yaml
repositories:
  mon-nouveau-repo:
    team_owner: dev              # doit correspondre à une team existante (dev, ia-ing, data)
    visibility: private
    description: "..."
    topics: ["..."]
    data_classification: interne # public | interne | confidentiel
    criticality: faible           # faible | moyen | eleve
```

```bash
git checkout -b ajout-mon-nouveau-repo
git add repos.yaml && git commit -m "Ajout de mon-nouveau-repo"
git push -u origin ajout-mon-nouveau-repo
```

Ouvre une pull request — le plan se poste en commentaire, la ou les
équipes concernées par ce diff précis y sont automatiquement
mentionnées. 1 approbation suffit. Le merge déclenche l'apply.

**Supprimer un dépôt ne fonctionne volontairement pas** en retirant
simplement son entrée de `repos.yaml` — chaque ressource porte un `lifecycle { prevent_destroy = true }`. Retirer cette protection est un
acte délibéré, distinct d'une simple modification de fichier.

### Structure des fichiers

| Fichier                                             | Contenu                                                                          |
| --------------------------------------------------- | -------------------------------------------------------------------------------- |
| `providers.tf`                                      | Provider GitHub, pointé sur `var.github_org`                                     |
| `backend.tf`                                        | Backend HCP Terraform (générique)                                                |
| `variables.tf`                                      | `github_org`                                                                     |
| `repos.yaml`                                        | Le fichier déclaratif, seul point d'entrée pour les équipes                      |
| `repos.tf`                                          | Logique `for_each` : crée repo + attribution team + custom properties par entrée |
| `.github/workflows/self-service-repos.yml`          | Pipeline plan → revue → apply, mentions d'équipe dynamiques                      |
| `.github/workflows/drift-detection-selfservice.yml` | Détection quotidienne de dérive                                                  |

---

## 6. Problèmes déjà rencontrés et leur solution

| Symptôme                                                                               | Cause                                                                                  | Solution                                                                                       |
| -------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| `403` sur `github_repository_custom_property` malgré un App bien configuré             | `values_editable_by` non réglé sur la définition, côté Fondations                      | Corriger `custom_properties.tf` dans Fondations : `values_editable_by = "org_and_repo_actors"` |
| Terraform bloqué, semble ne rien faire                                                 | Attente d'une saisie interactive pour une variable manquante en CI                     | Vérifier que `TF_VAR_github_org` est bien fourni et que `TF_INPUT: "false"` est présent        |
| `Error acquiring the state lock`                                                       | Job CI annulé en cours d'exécution                                                     | `terraform force-unlock <id>`                                                                  |
| Une team n'est pas mentionnée dans le commentaire de plan alors qu'elle devrait l'être | Le format de `repos.yaml` a changé, l'extraction par `grep`/`sed` ne le reconnaît plus | Vérifier que `team_owner: valeur` reste sur sa propre ligne, format inchangé                   |
| `Name must be unique` sur un repo qui existe déjà                                      | State désynchronisé                                                                    | `terraform import github_repository.this[\"nom-du-repo\"] nom-du-repo`                         |
