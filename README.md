# 📦 AWS SSM Toolkit

**aws-ssm-tools** is a modular command-line toolkit for managing connectis to EC2 via SSM, running commands across multiple AWS environments, and working efficiently with SSO.

This toolkit designed with the following in mind:

- Modular libraries (`lib/`)
- Small executable commands (`bin/`)
- Full support for AWS SSO (via Granted/Assume)
- Fast interactive instance selection (fzf or fallback menu)
- Safe error handling, no `eval`
- Works on Linux, macOS, and WSL

---

# 🚀 Features

### ✔ SSM Session Management
- Start shell sessions (`aws-ssm-connect`)  
- Start port-forwarding sessions from a config file  
- Execute commands on one or many EC2 instances (`aws-ssm-exec`)  
- Create temporary user accounts with sudo access (`aws-ssm-user`)  
- Remove temporary user accounts (`aws-ssm-user-remove`)  
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
curl -sSL https://raw.githubusercontent.com/kedwards/aws-ssm-tools/main/install.sh | bash
```

or:


```
wget -O - https://raw.githubusercontent.com/kedwards/aws-ssm-tools/main/install.sh | bash
```

This installs:

- toolkit → `~/.local/aws-ssm-tools/`
- commands → `~/.local/bin/`

Ensure your PATH includes:

```
export PATH="$HOME/.local/bin:$PATH"
```

---

# 🔄 Updating

```
aws-ssm-tools-update
```

or:

```
curl -sSL https://raw.githubusercontent.com/kedwards/aws-ssm-tools/main/update.sh | bash
```
or:

```
wget -O - https://raw.githubusercontent.com/kedwards/aws-ssm-tools/main/update.sh | bash
```

---

# 📂 Project Structure

```
aws-tools/
├── bin/
│   ├── aws-ssm-connect
│   ├── aws-ssm-exec
│   ├── aws-ssm-user
│   ├── aws-ssm-user-remove
│   ├── aws-ssm-list
│   ├── aws-ssm-kill
│   ├── aws-env-run
│
└── lib/
    ├── init.sh
    ├── logging.sh
    ├── menu.sh
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

### 📝 Using Saved Commands

You can save frequently-used commands in a config file and select them interactively:

```bash
aws-ssm-exec --select              # select command and instances interactively
aws-ssm-exec -s i-abc i-def        # select command, specify instances
```

#### Configuration File

The commands configuration file can be placed in one of two locations (checked in order):

1. `~/.config/aws-ssm-tools/commands.config` (user config)
2. `<script-directory>/commands.config` (project directory)

**Format:** The configuration file uses a pipe-delimited format:

```
COMMAND_NAME|Description|Command to execute
```

- Lines starting with `#` are treated as comments and ignored
- Empty lines are ignored
- **COMMAND_NAME**: Short identifier for the command (no spaces)
- **Description**: Human-readable description shown in the menu
- **Command**: The actual shell command to execute

#### Quick Setup Example

Create your commands config file:

```bash
mkdir -p ~/.config/aws-ssm-tools
cat > ~/.config/aws-ssm-tools/commands.config << 'EOF'
# Format: COMMAND_NAME|Description|Command to execute

# System monitoring
disk-usage|Check disk usage|df -h
memory-info|Display memory information|free -h
system-uptime|Show system uptime|uptime
process-list|Show top processes|ps aux --sort=-%mem | head -20

# Docker management
docker-status|Check Docker containers status|docker ps -a
docker-clean|Clean up stopped containers and unused images|docker container prune -f && docker image prune -f

# Logs
tail-syslog|Tail system log|tail -f /var/log/syslog
EOF
```

#### Advanced Features

Commands can include:
- **Command substitutions** (run locally): `'$(cat ~/.ssh/id_rsa.pub)'`
- **Multiple commands** chained with `;` or `&&`
- **Complex logic** with conditionals using `if/then/else`
- **Remote variables** using `\$VARIABLE` (escaped, evaluated on remote host)

Example complex command:
```bash
setup-qp-user|Setup qp user with SSH key and sudo access|USERNAME=qp; SSH_KEY='$(cat ~/.ssh/id_rsa.pub)'; if ! id \$USERNAME &>/dev/null; then useradd -m -s /bin/bash \$USERNAME && echo User \$USERNAME created; else echo User \$USERNAME already exists; fi; mkdir -p /home/\$USERNAME/.ssh && chmod 700 /home/\$USERNAME/.ssh && echo \$SSH_KEY > /home/\$USERNAME/.ssh/authorized_keys && chmod 600 /home/\$USERNAME/.ssh/authorized_keys && chown -R \$USERNAME:\$USERNAME /home/\$USERNAME/.ssh && printf '%s ALL=(ALL) NOPASSWD: ALL\n' \$USERNAME > /etc/sudoers.d/user_temp_access && chmod 440 /etc/sudoers.d/user_temp_access && echo Setup complete for user \$USERNAME with sudo access
```

## 👤 Create/Remove temporary user accounts

Create a user account on remote instances with your local username, SSH key access, and passwordless sudo:

```
aws-ssm-user                      # interactive instance selection
aws-ssm-user i-0123456789abcdef0  # specific instance
aws-ssm-user my-server            # by instance name
```

This creates:
- User account matching your local username
- SSH authorized_keys from `~/.ssh/id_rsa.pub`
- Passwordless sudo via `/etc/sudoers.d/user_temp_access`

Remove the user account and clean up:

```
aws-ssm-user-remove
aws-ssm-user-remove i-0123456789abcdef0
```

This removes:
- User account and home directory
- All user processes
- Sudoers configuration file

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
