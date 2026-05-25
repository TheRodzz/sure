# Deploying Sure on Hetzner Cloud

This guide will help you deploy Sure on a Hetzner Cloud server with Docker Compose, including SSL certificates, security hardening, and automated backups.

## Prerequisites

Before starting, ensure you have:

- A Hetzner Cloud server (recommended: 4GB RAM, 2 CPU cores minimum)
- A domain name pointing to your server's IP address
- SSH access to your server
- Basic familiarity with Linux command line

## Step 1: Server Setup and Security

Connect to your Hetzner server and set up the basic environment:

```bash
# Connect to your server (replace with your server's IP)
ssh root@YOUR_SERVER_IP

# Update the system
apt update && apt upgrade -y

# Install essential packages
apt install -y curl wget git ufw fail2ban

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Add your user to docker group (replace 'your_username' with your actual username)
# If you are using root, you can skip this step
if [ "$(whoami)" != "root" ]; then
    usermod -aG docker "$(whoami)"
fi

# Configure firewall
ufw allow ssh
ufw allow 80
ufw allow 443
ufw --force enable

# Configure fail2ban for SSH protection
systemctl enable fail2ban
systemctl start fail2ban
```

## Step 2: Create Application Directory

```bash
# Create directory for the application
mkdir -p /opt/sure
cd /opt/sure

# Download the Docker Compose configuration
curl -o compose.yml https://raw.githubusercontent.com/we-promise/sure/main/compose.example.yml
```

## Step 3: Configure Environment Variables

Create a secure environment configuration:

```bash
# Create environment file
nano .env
```

Add the following content to the `.env` file (replace the values with your own):

```bash
# Generate a secure secret key
SECRET_KEY_BASE="$(openssl rand -hex 64)"

# Database configuration
POSTGRES_USER="sure_user"
POSTGRES_PASSWORD="$(openssl rand -base64 32)"
POSTGRES_DB="sure_production"

# Optional: OpenAI integration (add your API key if you want AI features)
# OPENAI_ACCESS_TOKEN="your_openai_api_key_here"
```

**Important Security Notes:**
- Never use the default values from the example file in production
- Keep your `.env` file secure and never commit it to version control
- The `SECRET_KEY_BASE` is critical for Rails security - keep it secret

## Step 4: Set Up Reverse Proxy with SSL

We'll use Nginx as a reverse proxy with Let's Encrypt SSL certificates:

```bash
# Install Nginx and Certbot
apt install -y nginx certbot python3-certbot-nginx

# Create Nginx configuration for your domain
nano /etc/nginx/sites-available/sure
```

Add this Nginx configuration (replace `yourdomain.com` with your actual domain):

```nginx
server {
    listen 80;
    server_name yourdomain.com www.yourdomain.com;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
    }
}
```

```bash
# Enable the site
ln -s /etc/nginx/sites-available/sure /etc/nginx/sites-enabled/
rm /etc/nginx/sites-enabled/default

# Test Nginx configuration
nginx -t

# Start Nginx
systemctl enable nginx
systemctl start nginx

# Get SSL certificate
certbot --nginx -d yourdomain.com -d www.yourdomain.com
```

## Step 5: Deploy the Application

Now let's deploy the Sure application:

```bash
# Navigate to the application directory
cd /opt/sure

# Pull the latest Docker images
docker compose pull

# Start the application
docker compose up -d

# Check if everything is running
docker compose ps

# View logs to ensure everything started correctly
docker compose logs -f
```

## Step 6: Test the Deployment

Verify your deployment is working:

```bash
# Check if the application is accessible
curl -I https://yourdomain.com

# Check Docker container health
docker compose ps
```

Now you can:

1. **Visit your application**: Go to `https://yourdomain.com` in your browser
2. **Create your admin account**: Click "Create your account" on the login page
3. **Set up your first family**: Follow the onboarding process

## Step 7: Set Up Automated Backups

### PostgreSQL (recommended: Databasus)

Sure’s Compose file includes [Databasus](https://databasus.com/) for scheduled PostgreSQL backups with local storage and offsite replication (S3, Cloudflare R2, Google Drive, Azure Blob, SFTP, FTP, NAS, rclone, and more).

```bash
sudo mkdir -p /opt/sure-data/backups
cd /opt/sure
docker compose --profile backup up -d
```

Configure backups in the Databasus UI (`http://127.0.0.1:4005` by default—use SSH port forwarding or a secured reverse proxy). Connect to host `db`, port `5432`, and your `POSTGRES_*` credentials. Add local storage at `/backups` plus at least one remote destination.

See **[PostgreSQL backups with Databasus](databasus.md)** for the full setup guide.

### Application uploads (ActiveStorage)

Databasus does not back up files in the `app-storage` volume. Archive them separately, for example with a daily cron job:

```bash
nano /opt/sure/backup-storage.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/opt/sure-data/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"
docker compose exec -T web tar -czf - /rails/storage > "$BACKUP_DIR/storage_backup_$DATE.tar.gz"
find "$BACKUP_DIR" -name "storage_backup_*.tar.gz" -mtime +7 -delete
```

```bash
chmod +x /opt/sure/backup-storage.sh
crontab -e
# 0 3 * * * /opt/sure/backup-storage.sh >> /var/log/sure-backup.log 2>&1
```

## Step 8: Set Up Basic Monitoring

Create a health check script to monitor your application:

```bash
# Install htop for system monitoring
apt install -y htop

# Create a simple health check script
nano /opt/sure/health-check.sh
```

Add this health check script:

```bash
#!/bin/bash
# Check if the application is responding
if curl -f -s https://yourdomain.com > /dev/null; then
    echo "$(date): Application is healthy"
else
    echo "$(date): Application is down - restarting"
    cd /opt/sure
    docker compose restart web worker
fi
```

```bash
# Make health check executable
chmod +x /opt/sure/health-check.sh

# Add to crontab to run every 5 minutes
crontab -e
```

Add this line:
```bash
*/5 * * * * /opt/sure/health-check.sh >> /var/log/sure-health.log 2>&1
```

## Maintenance Commands

Here are the essential commands for maintaining your deployment:

### Update the application:
```bash
cd /opt/sure
docker compose pull
docker compose up --no-deps -d web worker
```

### View logs:
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f web
docker compose logs -f worker
docker compose logs -f db
```

### Restart services:
```bash
# Restart all services
docker compose restart

# Restart specific service
docker compose restart web
```

### Check system resources:
```bash
# Docker resource usage
docker stats

# System resources
htop
df -h
```

### Restore from backup

- **PostgreSQL:** use the Databasus UI or follow [databasus.md](databasus.md). Legacy `.sql` dumps in `/opt/sure-data/backups` can still be restored with `psql` if needed.
- **Application storage:**

```bash
docker compose exec -T web tar -xzf /opt/sure-data/backups/storage_backup_YYYYMMDD_HHMMSS.tar.gz -C /
```

## Security Features

Your deployment includes several security measures:

1. **Firewall**: Only ports 22 (SSH), 80 (HTTP), and 443 (HTTPS) are open
2. **Fail2ban**: Protects against brute force attacks on SSH
3. **SSL/TLS**: Automatic HTTPS with Let's Encrypt certificates
4. **Environment variables**: Sensitive data stored securely in `.env` file
5. **Non-root containers**: Application runs as non-root user
6. **Regular updates**: Keep your system and Docker images updated

## Troubleshooting

### Common Issues and Solutions

**Application won't start:**
```bash
# Check logs for errors
docker compose logs -f

# Check if ports are available
netstat -tulpn | grep :3000
```

**Database connection issues:**
```bash
# Check database container
docker compose logs db

# Test database connection
docker compose exec db psql -U sure_user -d sure_production -c "SELECT 1;"
```

**SSL certificate issues:**
```bash
# Renew certificates
certbot renew --dry-run

# Check certificate status
certbot certificates
```

**Out of disk space:**
```bash
# Check disk usage
df -h

# Clean up Docker images
docker system prune -a

# Clean up old local backup files (if not managed by Databasus retention)
find /opt/sure-data/backups -name "storage_backup_*.tar.gz" -mtime +7 -delete
```

**Application is slow:**
```bash
# Check system resources
htop
docker stats

# Check if containers are healthy
docker compose ps
```

## Performance Optimization

For better performance on Hetzner Cloud:

1. **Use SSD storage**: Hetzner Cloud provides NVMe SSD storage by default
2. **Choose appropriate server size**: 
   - Minimum: CX21 (2 vCPU, 4GB RAM)
   - Recommended: CX31 (2 vCPU, 8GB RAM) for multiple users
3. **Enable swap** (if needed):
   ```bash
   fallocate -l 2G /swapfile
   chmod 600 /swapfile
   mkswap /swapfile
   swapon /swapfile
   echo '/swapfile none swap sw 0 0' >> /etc/fstab
   ```

## Backup Strategy

1. **PostgreSQL:** Databasus with local path `/opt/sure-data/backups` plus at least one offsite storage (see [databasus.md](databasus.md))
2. **ActiveStorage:** optional `backup-storage.sh` cron for `/rails/storage`
3. **Databasus metadata:** back up the `databasus-data` volume and encryption `secret.key` offsite
4. **Hetzner snapshots:** optional full-VM snapshots for disaster recovery

Configure retention and notifications in the Databasus UI rather than ad-hoc `find … -mtime` rules for database dumps.

## Next Steps

After successful deployment:

1. **Create your admin account** at `https://yourdomain.com`
2. **Set up your first family** in the application
3. **Configure bank connections** (if using Plaid integration)
4. **Set up additional users** as needed
5. **Monitor your deployment** using the health check logs

## Support

If you encounter issues:

1. Check the [troubleshooting section](#troubleshooting) above
2. Review the application logs: `docker compose logs -f`
3. Check system resources: `htop` and `df -h`
4. Open a discussion in our [GitHub repository](https://github.com/we-promise/sure/discussions)

## Security Reminders

- Keep your server updated: `apt update && apt upgrade`
- Monitor your logs regularly: `/var/log/sure-backup.log` and `/var/log/sure-health.log`
- Use strong passwords for all accounts
- Consider setting up SSH key authentication instead of password authentication
- Regularly review your firewall rules: `ufw status`
- Monitor your SSL certificate expiration: `certbot certificates`
