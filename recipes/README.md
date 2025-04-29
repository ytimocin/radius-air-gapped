# Terraform Recipes for Air-Gapped Environments

## How to

### Publish Recipes

```bash
# First login to GitHub Container Registry
export GITHUB_TOKEN=your_github_personal_access_token
echo $GITHUB_TOKEN | docker login ghcr.io -u ytimocin --password-stdin

# Then publish the recipes
./publish.sh -d ./azure -n ghcr.io/ytimocin/terraform-recipes -t v1.0.0
```

### Serve Terraform Recipes

```bash
./serve.sh -n ghcr.io/ytimocin/terraform-recipes -t v1.0.0
```
