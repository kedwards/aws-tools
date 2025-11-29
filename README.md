# 📦 AWS Tools – AWS Profile & SSM Toolkit

**aws-tools** is a modular command-line toolkit for managing AWS CLI profiles, switching environments, connecting to EC2 via SSM, running commands across multiple AWS environments, and working efficiently with SSO.

This toolkit designed with the following in mind:

- Modular libraries (`lib/`)
- Small executable commands (`bin/`)
- Full support for AWS SSO (via Granted/Assume)
- Fast interactive instance selection (fzf or fallback menu)
- Safe error handling, no `eval`
- Works on Linux, macOS, and WSL

---

# 🚀 Features

### ✔ AWS Profile Management
- Login with SSO via Granted/assume  
- Switch profiles safely  
- Unset or fully clear SSO sessions  
- Inspect active identity (`aws-whoami`)

### ✔ SSM Session Management
- Start shell sessions (`aws-ssm-connect`)  
- Start port-forwarding sessions from a config file  
- Execute commands on one or many EC2 instances  
- List and kill active SSM sessions  

### ✔ Environment Automation
Run commands across multiple AWS environments and regions:

```
aws-env-run "aws s3 ls"
aws-env-run "aws ec2 describe-vpcs" prod:us-east-1 dev:us-west-2
```

### ✔ Interactive Menus
Uses `fzf` for selecting profiles, instances, and regions.  
Falls back to standard Bash menus if `fzf` is not installed.

### ✔ Easy Installation / Updating
- No sudo required  
- Installs entirely in `$HOME/.local`  
- Clean symlinks into `~/.local/bin`  

---

# 📥 Installation

### One-line curl install (recommended)

```
curl -sSL https://raw.githubusercontent.com/kedwards/aws-tools/main/install.sh | bash
```

This installs:

- toolkit → `~/.local/aws-tools/`
- commands → `~/.local/bin/`

Ensure your PATH includes:

```
export PATH="$HOME/.local/bin:$PATH"
```

---

# 🔄 Updating

```
aws-tools-update
```

or:

```
curl -sSL https://raw.githubusercontent.com/kedwards/aws-tools/main/update.sh | bash
```

---

# 📂 Project Structure

```
aws-tools/
├── bin/
│   ├── aws-profile
│   ├── aws-whoami
│   ├── aws-ssm-connect
│   ├── aws-ssm-exec
│   ├── aws-ssm-list
│   ├── aws-ssm-kill
│   ├── aws-env-run
│   └── aws-instances
│
└── lib/
    ├── init.sh
    ├── logging.sh
    ├── menu.sh
    ├── aws_profile.sh
    ├── aws_instances.sh
    ├── aws_ssm.sh
    └── aws_env_run.sh
```

---

# 📝 Configuration

## Optional: SSM forwarding config

Create `~/.ssmf.cfg`:

```
[my-db]
profile = prod
region = us-west-2
port = 5432
local_port = 5432
host = rds.custom.internal
url = http://localhost:5432/
name = prod-db-instance
```

Then run:

```
aws-ssm-connect --config
```

---

# 🧰 Usage Examples

## 🔐 Switch AWS profiles

```
aws-profile dev
aws-profile prod us-west-2
aws-profile -u
aws-profile -x
```

## 👤 Get current AWS identity

```
aws-whoami
```

## 💻 Connect to EC2 via SSM

```
aws-ssm-connect
aws-ssm-connect my-server
aws-ssm-connect i-0123456789abcdef0
aws-ssm-connect --config
```

## ⚡ Execute a command across instances

```
aws-ssm-exec "uptime" i-abc i-def
aws-ssm-exec "hostname"
```

## 🌎 Run commands across environments

```
aws-env-run "aws s3 ls" prod:us-east-1 dev:us-west-2
aws-env-run "aws ec2 describe-vpcs"
aws-env-run "echo ENV=#ENV REGION=#REGION"
```

## 📋 List & Kill SSM Sessions

```
aws-ssm-list
aws-ssm-kill
```

---

# 🧪 Dependencies

- `fzf` (optional, recommended)
- `granted` (for SSO)
- `jq` (JSON parsing)

---

# 🧯 Troubleshooting

### “assume not found”
Install Granted:

```
mise use -g granted
```

or:

```
brew install common-fate/granted/granted
```

or:

```
curl -s https://granted.dev/install | bash
```

### SSM failures  
Ensure SSM agent is running and instance has access to SSM endpoints.

### fzf missing  
Toolkit falls back to Bash menus.

---

# 🤝 Contributing

- No eval  
- No duplication  
- Pass shellcheck  
- Put shared logic in lib/  
- Keep commands small and simple  

---

# 📄 License

MIT
