# fileshare

2️⃣ UAT Variable Group – vg-uat

Name in Azure DevOps: VG-UAT
Purpose: UAT environment restore

Key	Value	Notes
ENVIRONMENT	uat	Used in logs & script
RESOURCE_GROUP	rg-uat	Resource group
VAULT_NAME	rsv-uat	Recovery Services vault
STORAGE_ACCOUNTS	stuatbackup001 stuatbackup002	Space-separated list
MAX_PARALLEL	3	Parallel restore jobs
POLL_INTERVAL	30	Seconds
SMTP_USER	ci-bot@gmail.com	Gmail account
SMTP_PASS	$(GMAIL_APP_PASS)	Secret
EMAIL_TO	uat-ops-team@company.com	Recipients
EMAIL_FROM	ci-bot@gmail.com	Sender
3️⃣ PROD Variable Group – vg-prod

Name in Azure DevOps: VG-PROD
Purpose: PROD environment restore

Key	Value	Notes
ENVIRONMENT	prod	Used in logs & script
RESOURCE_GROUP	rg-prod	Resource group
VAULT_NAME	rsv-prod	Recovery Services vault
STORAGE_ACCOUNTS	stprodbackup001 stprodbackup002	Space-separated list
MAX_PARALLEL	3	Parallel restore jobs
POLL_INTERVAL	30	Seconds
SMTP_USER	ci-bot@gmail.com	Gmail account
SMTP_PASS	$(GMAIL_APP_PASS)	Secret
EMAIL_TO	prod-ops-team@company.com	Recipients
EMAIL_FROM	ci-bot@gmail.com	Sender
✅ Notes:

Secrets: SMTP_PASS should be marked as secret in Azure DevOps Library.

Multiple storage accounts: STORAGE_ACCOUNTS is space-separated for iteration in your Bash script.

Parallelization: MAX_PARALLEL controls how many shares are restored concurrently.

Pipeline integration: Reference variable group in YAML like this:

variables:
- group: VG-PROD

# For Windows developers
git config --global core.autocrlf true   # Converts LF → CRLF on checkout, CRLF → LF on commit

# For Linux/macOS developers
git config --global core.autocrlf input  # Converts CRLF → LF on commit, leaves LF as-is