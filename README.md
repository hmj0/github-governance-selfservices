# github-governance-selfservices

Dépôt de création de dépôts en libre-service. Chaque équipe déclare ses
besoins dans `repos.yaml` ; ce dépôt matérialise chaque entrée en un vrai
dépôt GitHub, avec son attribution d'équipe, ses custom properties, et
un ensemble de fichiers de gouvernance/hygiène propagés automatiquement.
C'est la **Couche 2** de l'architecture décrite dans le rapport de
conception — changements fréquents, revue légère (1 approbation).

Le dépôt frère [`github-governance-foundations`](../github-governance-foundations)
constitue la Couche 1 : teams, rulesets et réglages généraux, dont ce
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

Même principe de state que Fondations : **HCP Terraform, mode Local**
— stockage et verrouillage seulement, l'exécution reste sur GitHub
Actions.

**Les 5 équipes propriétaires possibles** (valeur de `team_owner` dans
`repos.yaml`) : `consulting`, `ai-data-science`, `data-engineering`,
`data-analytics`, `product` — les 5 départements réels d'Artefact.
`admin` n'apparaît jamais ici : cette team gouverne la plateforme
elle-même, elle ne possède pas de dépôt créé via ce mécanisme.

---

## 2. Prérequis

Identiques à `github-governance-foundations` §3 — compte HCP Terraform
avec accès à la même organisation HCP, droits Owner/Admin sur
l'organisation GitHub cible le temps de la mise en place initiale.

**Prérequis supplémentaire, propre à ce dépôt** : le premier `apply` de
`github-governance-foundations` doit déjà avoir eu lieu — ce dépôt lit
les teams (`data.github_team.by_name`) qui n'existent qu'une fois
Fondations appliqué.

---

## 3. Mise en place initiale (une seule fois, par organisation)

### 3.1 — Créer le GitHub App dédié

Sur `github.com/organizations/<TON_ORG>/settings/apps/new` — **un App
distinct de celui de Fondations** (jamais de compte de service partagé
entre les deux couches) :

| Champ | Valeur |
|---|---|
| GitHub App name | `selfservice-governance-bot` (ou équivalent, unique sur tout GitHub) |
| Homepage URL | L'URL de l'organisation suffit |
| Webhook → Active | **Décoché** |

**Permissions à cocher — Repository permissions :**

(`github.com/settings/apps/selfservice-governance-bot/permissions`)

| Permission | Niveau |
|---|---|
| Administration | Read and write |
| Custom properties | Read and write |
| Contents | Read and write |
| Workflows | Read and write |

> Les deux dernières sont nécessaires à la propagation des fichiers de
> gouvernance (§6) : **Contents** pour écrire n'importe quel fichier
> dans un repo créé, **Workflows** en plus, spécifiquement, pour les
> fichiers sous `.github/workflows/` — GitHub protège ce dossier par
> une permission séparée, distincte de Contents, précisément parce
> qu'un workflow peut exécuter du code arbitraire. Sans Workflows :
> `403 Resource not accessible by integration` sur `pr-agent.yml` et
> `pin-actions.yml` uniquement (`dependabot.yml`, lui, hors de ce
> dossier, ne dépend que de Contents).

> Aucune Organization permission n'est nécessaire ici — ce dépôt ne lit
> les teams qu'en lecture seule (`data` source), jamais en écriture.

**Un point d'attention spécifique à ce dépôt** : même une fois les
permissions correctement cochées, l'écriture des custom properties
échoue tant que leur définition, côté Fondations
(`custom_properties.tf`), n'a pas `values_editable_by =
"org_and_repo_actors"`. Vérifier ce réglage en premier si un `403`
apparaît sur `github_repository_custom_property`.

Une fois créé : mêmes 3 étapes qu'en Fondations §4.1 (App ID, clé
privée, installation sur **All repositories**) —
`github.com/settings/apps/selfservice-governance-bot`. **Note l'App
ID** — il doit aussi être posé comme secret `SELFSERVICE_APP_ID` sur le
dépôt Fondations (voir son README §4.3), pour permettre le bypass de
ruleset décrit en §6.

### 3.2 — Créer le workspace HCP Terraform

Même organisation HCP que Fondations, nouveau workspace :

1. **New workspace → CLI-Driven Workflow**
2. Nom exact : `github-governance-selfservices`
3. **Execution Mode → Local (custom)**
   (`app.terraform.io/app/<TON_ORG_HCP>/workspaces/github-governance-selfservices/settings/general`)
4. Un token d'API peut être réutilisé (celui généré pour Fondations
   fonctionne aussi bien, HCP Terraform ne les scope pas par workspace
   par défaut)

### 3.3 — Poser les Secrets et Variables GitHub Actions

Sur ce dépôt → **Settings → Secrets and variables → Actions**
(`github.com/<TON_ORG>/github-governance-selfservices/settings/secrets/actions`).

**Onglet Secrets :**

| Nom | Valeur |
|---|---|
| `APP_ID` | L'App ID noté en 3.1 (celui de CE dépôt, pas celui de Fondations) |
| `APP_PRIVATE_KEY` | Contenu intégral du `.pem` |
| `HCP_TERRAFORM_TOKEN` | Le token HCP (réutilisable depuis Fondations) |

> `GEMINI_API_KEY` n'apparaît **volontairement pas** ici : c'est un
> secret d'organisation, posé une seule fois par Fondations et hérité
> automatiquement — le poser aussi ici serait redondant, et créerait
> deux sources de vérité pour la même valeur.

**Onglet Variables :**

| Nom | Valeur |
|---|---|
| `GH_ORG` | Même slug d'organisation que Fondations |
| `HCP_ORG` | Même organisation HCP que Fondations |

---

## 4. Le tout premier apply

Contrairement à Fondations, aucune contrainte de revue ne bloque ce
dépôt dès sa création (le ruleset général vient de Fondations, déjà
actif). Une PR normale fonctionne donc dès le début — mais pour un tout
premier test rapide, un apply local reste possible, avec un PAT dédié
(distinct de celui de Fondations, ou le même — les scopes se recoupent) :

| Scope à cocher | Pourquoi |
|---|---|
| `repo` | Création des dépôts, attribution aux teams, écriture des custom properties et des fichiers propagés |
| `read:org` | Lecture des teams (`data "github_team"`) — en lecture seule, `admin:org` n'est pas nécessaire ici contrairement à Fondations |

```bash
git clone https://github.com/<TON_ORG>/github-governance-selfservices.git
cd github-governance-selfservices

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
    team_owner: consulting        # consulting | ai-data-science | data-engineering | data-analytics | product
    visibility: private
    description: "..."
    topics: ["..."]
    data_classification: interne  # public | interne | confidentiel
    criticality: faible            # faible | moyen | eleve
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
simplement son entrée de `repos.yaml` — le repo, l'attribution d'équipe
et les custom properties portent chacun un `lifecycle { prevent_destroy
= true }`. Retirer cette protection est un acte délibéré, distinct
d'une simple modification de fichier. Les fichiers propagés (§6), eux,
n'ont volontairement pas cette protection — voir §6 pour le
raisonnement.

### Structure des fichiers

| Fichier | Contenu |
|---|---|
| `providers.tf` | Provider GitHub, pointé sur `var.github_org` |
| `backend-services.tf` | Backend HCP Terraform (générique) |
| `variables.tf` | `github_org` |
| `repos.yaml` | Le fichier déclaratif, seul point d'entrée pour les équipes |
| `repos.tf` | Logique `for_each` : crée repo + attribution team + custom properties + fichiers propagés par entrée |
| `.github/workflows/pr-agent.yml` | Copie de référence — revue automatisée par IA, propagée à chaque nouveau repo (§6) |
| `.github/dependabot.yml` | Copie de référence — écosystème github-actions, propagée à chaque nouveau repo (§6) |
| `.github/workflows/pin-actions.yml` | Copie de référence — épinglage tag→SHA des actions, propagée à chaque nouveau repo (§6) |
| `.github/workflows/self-service-repos.yml` | Pipeline plan → revue → apply, mentions d'équipe dynamiques |
| `.github/workflows/drift-detection-selfservice.yml` | Détection quotidienne de dérive |

---

## 6. Fichiers de gouvernance propagés à chaque nouveau dépôt

Trois fichiers sont copiés automatiquement dans chaque repo créé, lus
depuis leur propre copie de référence dans **ce** dépôt (via
`github_repository_file`, un `for_each` combiné repo × fichier dans
`repos.tf`) :

- **`pr-agent.yml`** — revue de code par IA (Gemini), authentifiée via
  le secret d'organisation `GEMINI_API_KEY` (posé par Fondations,
  hérité automatiquement — rien à faire ici)
- **`dependabot.yml`** — met à jour le SHA d'une action déjà épinglée
  quand une nouvelle version sort ; ne convertit jamais un tag en SHA
  de lui-même
- **`pin-actions.yml`** — convertit une référence par tag (`@v4`,
  `@main`) en SHA exact, la première fois ; complémentaire de
  Dependabot, pas redondant

**Modifier une de ces trois copies et appliquer met à jour l'ensemble
des dépôts déjà gérés en une seule fois**, sans toucher à `repos.yaml`.

**Pourquoi aucune de ces trois ressources n'a `prevent_destroy`**,
contrairement au reste de ce fichier : ce sont des fichiers de confort,
recréés par la prochaine dérive détectée s'ils disparaissent — pas des
ressources de gouvernance critiques comme le repo lui-même, l'accès
d'équipe ou les custom properties.

**Pourquoi ce commit direct sur `main` ne casse pas le ruleset
général** (qui exige normalement une PR) : `selfservice-governance-bot`
est explicitement ajoutée comme `bypass_actors` (type `Integration`)
dans `rulesets.tf`, côté Fondations — ce commit est assimilé à une
initialisation de dépôt, comme `auto_init`, pas à un changement
ordinaire. Voir le README de Fondations §7 pour le détail et le point
de vigilance associé.

---

## 7. Problèmes déjà rencontrés et leur solution

| Symptôme | Cause | Solution |
|---|---|---|
| `403` sur `github_repository_custom_property` malgré un App bien configuré | `values_editable_by` non réglé sur la définition, côté Fondations | Corriger `custom_properties.tf` dans Fondations : `values_editable_by = "org_and_repo_actors"` |
| `403 Resource not accessible by integration` sur `pr-agent.yml` ou `pin-actions.yml` uniquement (pas sur `dependabot.yml`) | Permission "Workflows" absente sur le GitHub App — distincte de "Contents" | Ajouter Workflows (Read and write) sur `github.com/settings/apps/selfservice-governance-bot/permissions`, puis valider l'approbation sur `github.com/organizations/<TON_ORG>/settings/installations` |
| `409 Repository rule violations found — Changes must be made through a pull request` sur `github_repository_file` | Le ruleset général bloque le commit direct sur `main` que fait la propagation de fichiers | Ajouter `selfservice-governance-bot` comme `bypass_actors` (type `Integration`) dans `rulesets.tf`, côté Fondations (voir §6) |
| Terraform bloqué, semble ne rien faire | Attente d'une saisie interactive pour une variable manquante en CI | Vérifier que `TF_VAR_github_org` est bien fourni et que `TF_INPUT: "false"` est présent |
| `Error acquiring the state lock` | Job CI annulé en cours d'exécution | `terraform force-unlock <id>` |
| Une team n'est pas mentionnée dans le commentaire de plan alors qu'elle devrait l'être | Le format de `repos.yaml` a changé, l'extraction par `grep`/`sed` ne le reconnaît plus | Vérifier que `team_owner: valeur` reste sur sa propre ligne, format inchangé |
| `Name must be unique` sur un repo qui existe déjà | State désynchronisé | `terraform import github_repository.this[\"nom-du-repo\"] nom-du-repo` |
| `422 Unable to save ... because you can't delete options that are in use` côté Fondations lors d'un changement de nom d'équipe | Un repo ici référence encore l'ancienne valeur de `team_owner` | Corriger `repos.yaml` avec la nouvelle valeur et appliquer ce dépôt *avant* que Fondations ne retire l'ancienne valeur du schéma |