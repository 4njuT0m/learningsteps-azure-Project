# Part 1 infrastructure

Files to rebuild the LearningSteps Part 1 deployment without doing every step by hand. The full description of the setup is in [docs/part1/WRITEUP.md](../docs/part1/WRITEUP.md).

| Folder | What it does |
|---|---|
| `azure-template/` | Azure resources (VNet, subnets, NSGs, NAT gateway, VMs, public IPs), exported from the Azure Portal |
| `vm-setup/setup-vm-db.sh` | Installs and locks down PostgreSQL on vm-db, creates the user, database and table |
| `vm-setup/setup-vm-api.sh` | Installs the API on vm-api: service user, venv, `.env`, systemd service, nginx |
| `vm-setup/learningsteps.service` | systemd unit for uvicorn on 127.0.0.1:8000 |
| `vm-setup/nginx-learningsteps.conf` | nginx reverse proxy from port 80 to 127.0.0.1:8000 |

No passwords are stored here. Both scripts ask for the `ls_app` password when they run.

## Redeploy

### 1. Azure resources

Either create them in the Portal with the values in the writeup, or deploy the exported template:

```bash
az group create --name rg-learningsteps --location germanywestcentral
SUB_ID=$(az account show --query id -o tsv)
MY_IP=$(curl -s https://api.ipify.org)
MY_EMAIL="you@example.com"
sed -e "s/<subscription-id>/${SUB_ID}/g" -e "s/<your-ip>/${MY_IP}/g" -e "s/<your-email>/${MY_EMAIL}/g" \
  infra-part1/azure-template/template.json > /tmp/template.json
az deployment group create --resource-group rg-learningsteps --template-file /tmp/template.json
```

The template uses `<subscription-id>`, `<your-ip>` and `<your-email>` as placeholders. Set `MY_EMAIL` to the address for auto-shutdown notifications. The `sed` line fills in all three, so none of them is stored in the repo. Run these commands in bash, for example in the Dev Container. The template was exported from a running setup, so it may need small fixes before it deploys cleanly. Test it in a new resource group before relying on it.

### 2. Database server (vm-db)

Generate a password first (`openssl rand -hex 24`) and keep it safe.

```bash
ssh vm-db
sudo apt update && sudo apt install -y git
git clone https://github.com/4njuT0m/learningsteps-azure-Project.git
sudo bash learningsteps-azure-Project/infra-part1/vm-setup/setup-vm-db.sh
```

### 3. API server (vm-api)

```bash
ssh vm-api
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/4njuT0m/learningsteps-azure-Project.git /opt/learningsteps
sudo bash /opt/learningsteps/infra-part1/vm-setup/setup-vm-api.sh
```

Use the same password as in step 2.

### 4. Check

Open `http://<vm-api-public-ip>/docs`.

## Notes

- The scripts expect the private IPs 10.0.1.4 (vm-api) and 10.0.2.4 (vm-db). The NSG rules use the same IPs.
- Both scripts can be run again. They skip what already exists.
- The scripts repeat the manual steps from the writeup. They have not been tested on a fresh deployment yet.
