# LearningSteps Part 1: Azure 2-Tier Deployment

LearningSteps is a FastAPI app with a PostgreSQL database for tracking a daily learning journal. In this project I deployed it on Microsoft Azure as a 2-tier setup: the API server in a public subnet and the database server in a private subnet that cannot be reached from the internet.

- API: `http://20.52.233.190/docs`
- Region: Germany West Central
- Resource group: `rg-learningsteps`
- Code: my fork `4njuT0m/learningsteps-azure-Project`, using the Reference Implementation path from the project brief

## Architecture

![Architecture](screenshots/p1-architecture.png)

| Resource | Name | Details |
|---|---|---|
| Virtual network | `vnet-learningsteps` | 10.0.0.0/16 |
| Public subnet | `snet-public` | 10.0.1.0/24, NSG `nsg-public` |
| Private subnet | `snet-private` | 10.0.2.0/24, NSG `nsg-private`, NAT gateway |
| API server | `vm-api` | Ubuntu 24.04, Standard_D2s_v6, private IP 10.0.1.4, public IP 20.52.233.190 |
| Database server | `vm-db` | Ubuntu 24.04, Standard_D2s_v6, private IP 10.0.2.4, no public IP |
| NAT gateway | `nat-learningsteps` | Standard V2, public IP 135.220.249.124, outbound only |

| NSG | Priority | Action | Port | Source |
|---|---|---|---|---|
| nsg-public | 100 | Allow | TCP 80 | Internet |
| nsg-public | 110 | Allow | TCP 22 | My IP only |
| nsg-private | 100 | Allow | TCP 5432 | 10.0.1.4 |
| nsg-private | 110 | Allow | TCP 22 | 10.0.1.4 |
| nsg-private | 4000 | Deny | Any | Any |

## What I did

### 1. Local setup

- Forked `CyberstepsDE/learningsteps` to `4njuT0m/learningsteps-azure-Project` on GitHub.
- Cloned the fork to my Windows laptop.
- Configured Git for Windows to keep Linux line endings (`core.autocrlf input`) and cloned the repo again.
- Created the local `.env` file from `.env-sample` and confirmed Git ignores it.
- Installed Ubuntu in WSL 2 and set it as the default distro.
- Enabled Docker Desktop's WSL integration for Ubuntu and checked Docker works from inside Ubuntu.
- Opened the project in the VS Code Dev Container (FastAPI app + PostgreSQL) on Docker Desktop.
- Marked the repo as trusted inside the container (`git config --global --add safe.directory /workspaces`).
- Started the app with `./start.sh`. On `main`, GET `/entries/{entry_id}` returned 501 (not implemented).

![Fork](screenshots/p1-01-github-fork.png)
![Git check](screenshots/p1-02-git-check.png)
![WSL distros](screenshots/p1-03-wsl-distros.png)
![Docker WSL integration](screenshots/p1-04-docker-wsl-integration.png)
![Docker in Ubuntu](screenshots/p1-05-docker-in-ubuntu.png)
![Dev Container connected](screenshots/p1-06-devcontainer-connected.png)
![Swagger UI local](screenshots/p1-08-swagger-docs.png)
![GET 501](screenshots/p1-09-get-entry-501.png)

### 2. Reference code

- Chose the Reference Implementation path, so this part focuses on the Azure infrastructure.
- Added the original repository as the `upstream` remote. My fork only had `main`, so the `reference` branch had to come from there.
- Created branch `feature/reference-implementation` and copied in the reference files with `git restore --source upstream/reference -- .`. A normal merge conflicted in `api/main.py`.
- Rebuilt the Dev Container, because the reference adds the Azure CLI. The rebuild created `.devcontainer/devcontainer-lock.json`, which I committed with the change.
- Committed only the project files (not my `docs/` folder), pushed the branch and opened a pull request into my fork's `main`.
- Tested locally before merging: GET by ID returned 200 for an existing entry and 404 for an unknown one, and `test_api.py` passed.
- Merged the pull request and deleted the branch.

![Git remotes](screenshots/p1-09b-git-remotes.png)
![Reference changes](screenshots/p1-10-reference-changes.png)
![GET 200](screenshots/p1-13-get-entry-200.png)
![GET 404](screenshots/p1-14-get-entry-404.png)
![test_api.py local](screenshots/p1-16-test-api-local.png)
![test_api.py local](screenshots/p1-16b-test-api-local.png)

### 3. Design and Azure check

- Region: Germany West Central.
- Checked the vCPU quota: 0 of 10 in use. Two Standard_D2s_v6 VMs need 4.
- No resource groups were left from my first attempt.
- Drew the architecture diagram above before building anything.

![Quota](screenshots/p1-17b-azure-quota.png)

### 4. Network

- Created resource group `rg-learningsteps`.
- Created VNet `vnet-learningsteps` (10.0.0.0/16) with `snet-public` (10.0.1.0/24) and `snet-private` (10.0.2.0/24).
- Created `nsg-public` and associated it with `snet-public`: allow TCP 80 from Internet and TCP 22 from my IP.
- Created `nsg-private` and associated it with `snet-private`: allow TCP 5432 and 22 only from 10.0.1.4, deny all other inbound traffic at priority 4000. Azure shows a warning on the deny rule because it overrides the default rules for VNet and load balancer traffic. That is what I wanted.
- Created NAT gateway `nat-learningsteps` with its own public IP and attached it to `snet-private` only.

![Subnets](screenshots/p1-18-vnet-subnets.png)
![nsg-public](screenshots/p1-19-nsg-public-rules.png)
![nsg-private](screenshots/p1-20-nsg-private-rules.png)
![NAT gateway](screenshots/p1-21-nat-gateway.png)

### 5. Virtual machines

- Created an Ed25519 SSH key pair on my laptop. Only the public key is in Azure.
- Created `vm-api` in `snet-public` with a Standard public IP, and `vm-db` in `snet-private` with no public IP. Both: Ubuntu 24.04, Standard_D2s_v6, SSH key login only, no NSG on the network interface, auto-shutdown enabled.
- Set static private IPs: 10.0.1.4 for vm-api and 10.0.2.4 for vm-db, because the NSG rules depend on them.
- Connected to vm-api from my laptop, and to vm-db only through vm-api as a jump host (`ProxyJump` in my SSH config).
- The vm-db overview shows a public IP labelled "NAT gateway". That is the NAT gateway's outbound address, not an IP on the VM.
- Updated both VMs with `apt`. On vm-db, `curl https://api.ipify.org` returned 135.220.249.124, the NAT gateway's IP.

![vm-api overview](screenshots/p1-22-vm-api-overview.png)
![SSH vm-api](screenshots/p1-23-ssh-vm-api.png)
![vm-db overview](screenshots/p1-24-vm-db-overview.png)
![SSH vm-db and NAT check](screenshots/p1-25-ssh-vm-db-nat.png)

### 6. PostgreSQL on vm-db

- Installed PostgreSQL 16 and enabled it on boot.
- Created user `ls_app` (password set with `\password`, so it is not in the shell history) and database `learning_journal` owned by `ls_app`.
- Set `listen_addresses = 'localhost,10.0.2.4'`. `ss` showed PostgreSQL listening only on 127.0.0.1:5432 and 10.0.2.4:5432.
- Kept Ubuntu's default local rules in `pg_hba.conf` and added one network rule: `learning_journal`, user `ls_app`, from 10.0.1.4/32, scram-sha-256.
- Created the `entries` table by running `database_setup.sql` as `ls_app`.
- From vm-api, `ls_app` connected and listed the `entries` table. User `postgres` was rejected with "no pg_hba.conf entry", with and without SSL.

![listen_addresses](screenshots/p1-26-pg-listen.png)
![pg_hba.conf](screenshots/p1-27-pg-hba.png)
![psql from vm-api](screenshots/p1-28-psql-from-api.png)
![postgres rejected](screenshots/p1-29-pg-reject-postgres.png)

### 7. API on vm-api

- Installed python3-venv, nginx and git.
- Created a system user `learningsteps` with no login shell. The app runs as this user.
- Cloned my fork to `/opt/learningsteps`, created a virtual environment and installed `api/requirements.txt`.
- Put `DATABASE_URL` in `/opt/learningsteps/.env`, owned by `learningsteps` with permissions 600.
- Created a systemd service `learningsteps` that runs uvicorn on 127.0.0.1:8000, starts on boot and restarts on failure.
- On the VM, `/docs` returned 200 and `/entries` returned `{"entries":[],"count":0}`, so the app could reach the database.
- Set up nginx as a reverse proxy from port 80 to 127.0.0.1:8000 and removed the default site.
- The API works at `http://20.52.233.190/docs`. Port 8000 is not reachable from the internet.

![.env permissions](screenshots/p1-30-env-permissions.png)
![Service status](screenshots/p1-31-service-status.png)
![Local curl](screenshots/p1-32-local-curl.png)
![nginx -t](screenshots/p1-33-nginx-test.png)
![Docs on public IP](screenshots/p1-34-docs-public-ip.png)
![Port 8000 blocked](screenshots/p1-35-port-8000-blocked.png)

### 8. Testing

| Success criterion | Result | Evidence |
|---|---|---|
| API reachable via public IP | `/docs` loads at `http://20.52.233.190` | p1-34 |
| All CRUD operations work | Create, update and delete through the public IP returned 200. `test_api.py` on vm-api passed all tests. | p1-36 to p1-39b |
| Database strictly internal | Port 5432 closed on both public IPs. IP flow verify: internet to 10.0.2.4:5432 denied by `Deny-All-Inbound`, vm-api allowed by `Allow-PostgreSQL-from-API`. | p1-40 to p1-42 |
| Data persists | After restarting vm-api and then vm-db, `/entries` returned the same entry as before. All services started on boot. | p1-43, p1-44 |
| NSGs least privilege | SSH from my phone's hotspot timed out. Only my IP can SSH to vm-api. | p1-19, p1-20, p1-45 |

![Create](screenshots/p1-36-crud-create.png)
![Update](screenshots/p1-37-crud-update.png)
![Delete](screenshots/p1-38-crud-delete.png)
![test_api.py on vm-api](screenshots/p1-39a-test-api-vm.png)
![test_api.py on vm-api](screenshots/p1-39b-test-api-vm.png)
![Port 5432 blocked](screenshots/p1-40-port-5432-blocked.png)
![IP flow denied](screenshots/p1-41-ip-flow-denied.png)
![IP flow allowed](screenshots/p1-42-ip-flow-allowed.png)
![After vm-api restart](screenshots/p1-43-persist-after-api-restart.png)
![After vm-db restart](screenshots/p1-44-persist-after-db-restart.png)
![SSH from other network](screenshots/p1-45-ssh-other-network.png)

## Security decisions

- The database server has no public IP and sits in its own private subnet. It can only be reached from inside the VNet.
- `nsg-public` only opens port 80 to the internet. SSH is allowed from my IP only.
- `nsg-private` only allows PostgreSQL and SSH from the API server (10.0.1.4). The deny rule at 4000 is needed because Azure's default rule `AllowVnetInBound` (65000) would otherwise allow all traffic inside the VNet.
- The private subnet uses a NAT gateway for outbound traffic, so vm-db can install updates but nothing on the internet can connect to it.
- SSH uses keys only. vm-db can only be reached by jumping through vm-api.
- PostgreSQL has a second layer of protection: it only listens on the private IP, and `pg_hba.conf` only allows `ls_app` from 10.0.1.4 to `learning_journal`. The admin user `postgres` cannot log in over the network.
- The app uses its own database user, not `postgres`, and runs as a system user with no login shell, not as root.
- uvicorn only listens on 127.0.0.1. nginx is the only thing open to the internet, on port 80.
- The database password is only in `/opt/learningsteps/.env` (permissions 600) and not in Git. Screenshots do not show passwords, keys, my subscription ID or my home IP.
- Private IPs are static, so the NSG rules stay correct after a restart.

## Challenges

- **Windows line endings.** Git for Windows changed all files to Windows line endings, so every file was bigger than on GitHub by one byte per line (`start.sh`: 913 to 946 bytes). A shell script like that fails in a Linux container. I set `core.autocrlf input` and cloned again.
- **Dev Container: "No space left on device".** The log showed VS Code installing itself inside `docker-desktop`, Docker's internal WSL distro. It was the only distro, so it was the default, and it has almost no space. Docker's engine also stopped responding during these attempts. I installed Ubuntu in WSL, made it the default and enabled Docker's WSL integration for it.
- **Git "dubious ownership" in the container.** The mounted folder belongs to a different user than `vscode`. I marked my own repo as trusted with `safe.directory`.
- **Merge conflict with the reference branch.** The original `main` and `reference` both changed `api/main.py`. I copied the reference files with `git restore` instead of merging.
- **`python3-venv` had no installation candidate.** The new vm-api had never downloaded its package lists. `sudo apt update` fixed it.
- **Git "dubious ownership" on vm-api.** I cloned with sudo, so the repo belonged to root. I ran Git as the owner instead of adding an exception.
- **Database did not exist.** `database_setup.sql` failed with `database "learning_journal" does not exist`. The login worked, so the `CREATE DATABASE` line had never run. I checked with `\l`, created the database and ran the script again.
- **Reboot test timed out.** The browser first timed out on `/entries`, most likely because I tested while a VM was still starting. The app log showed `ConnectionRefusedError` on 10.0.2.4:5432 while PostgreSQL was starting. When vm-db was back, the API recovered by itself.

## Key learnings

- Azure NSGs have default rules that allow all traffic inside the VNet. "Only port 5432 from vm-api" is only true with my own deny rule.
- A NAT gateway gives outbound internet access without making a VM reachable from the internet.
- Network rules and database rules work together. Even if an NSG rule were wrong, `pg_hba.conf` would still block other users and hosts.
- Error messages tell you where to look. "Connection timed out" means nothing answered. "Connection refused" means the machine answered but nothing listened on the port. "Password authentication failed" and "database does not exist" are different problems.
- Testing before merging and testing after restarting are both needed. A service that works now may not start again after a reboot unless it is enabled.

## Known issues

- The API uses HTTP, not HTTPS. HTTPS needs a domain and a certificate, which was not part of this part.
- nginx shows its version in the response headers (`server: nginx/1.24.0 (Ubuntu)`). `server_tokens off;` would hide it.
- The reference code's PATCH replaces the whole entry with the fields sent instead of merging them. Updating only `work` emptied `struggle` and `intention`. This comes from the reference code, not from the deployment.
