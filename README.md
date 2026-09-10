# github-governance-selfservice (POC)

## 1. Pré-requis
- Le dossier `github-governance-foundations` doit déjà avoir été appliqué (les 4 teams
  doivent exister dans l'org) — sinon `data "github_team"` échouera à l'étape plan.
- Même token que Fondations (`GITHUB_TOKEN`, scope `admin:org`).

## 2. Configuration locale
```bash
export GITHUB_TOKEN="ton_token_ici"
cp terraform.tfvars.example terraform.tfvars
# édite terraform.tfvars avec le même nom d'org que Fondations
```

## 3. Initialisation
```bash
terraform init
terraform plan
```
Attendu : **3 to add**
- `github_repository.this["poc-service-api"]`
- `github_team_repository.this["poc-service-api"]`
- `data.github_team.by_name["dev"]` (une lecture, pas une création, mais apparaît dans le plan)

## 4. Application
```bash
terraform apply
```
Vérifie ensuite sur `github.com/<ton-org>/poc-service-api` que le repo existe,
et sur l'onglet "Teams" de ce repo que `team-dev` apparaît avec la permission "Write".

## Note
Ce POC ne pose pas encore les custom properties (`team_owner`, `criticality`, etc.) sur le
repo créé — ça viendra une fois que `custom_properties.tf` de Fondations sera passé avec
succès (actuellement en attente de propagation du plan Team, voir Fondations).
