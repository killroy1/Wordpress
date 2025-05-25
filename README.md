# WordPress Deployment 

This document provides a detailed explanation of the steps taken to set up the WordPress site and database using Terraform, the design decisions made, challenges encountered, and additional considerations for production environments.

This is meant to be run in your local device, please do note i meantion that in this document.

---

## **1. Infrastructure Setup**

### **Steps to Deploy the Infrastructure**
1. **Clone the Repository:**
   Ensure you have the Terraform code in your local environment:
   ```bash
   git clone https://github.com/killroy1/WordKord
   cd Wordpress-1/terraform
   ```

2. **Initialize Terraform:**

** Assumption Az Cli is install **

** Assumption terraform is install **

   Run the following command to initialize Terraform and download the required providers:
   ```bash
   terraform init
   ```

3. **Review the Plan:**
   Generate a plan to see the resources that will be created:
   ```bash
   terraform plan
   ```

4. **Apply the Configuration:**
   Deploy the infrastructure by running:
   ```bash
   terraform apply
   ```
   Confirm the prompt with `yes`.

5. **Access the WordPress Site:**
   Once the deployment is complete, access the WordPress site using the public IP of the Load Balancer:
   ```plaintext
   http://<load-balancer-public-ip>
   ```

---

## **2. Design Decisions**

![Mywordypreskrod](https://github.com/user-attachments/assets/efb96462-f67d-491a-9f90-e1fa74409290)


---
### **Persistence**
- **WordPress Content:**
  - WordPress content (e.g., uploads, themes, plugins) is stored on an NFS share mounted to `/var/www/html`. This ensures persistence even if the VMSS instances are replaced.
  - The NFS share is backed by an Azure Storage Account with private containers for security.

- **Database:**
  - The MySQL Flexible Server is used for the WordPress database. It is configured with:
    - **Backup Retention:** 20 days.
    - **High Availability:** Enabled with zone redundancy.
    - **Secure Transport:** Enforced with `require_secure_transport = "ON"`.

### **Security**
- **Network Security Group (NSG):**
  - HTTP (port 80) is open to all for public access.
  - SSH (port 22) is restricted to the public IP of the administrator using `data "http" "myip"`.

- **Database Security:**
  - Firewall rules restrict access to the MySQL Flexible Server to the VMSS instances' IPs.
  - SSL/TLS is enforced for database connections.

- **VMSS Security:**
  - SSH access is configured with an SSH key pair.
  - Password authentication is disabled.

### **Scalability**
- The Virtual Machine Scale Set (VMSS) is configured with autoscaling based on CPU usage:
  - Scale out when CPU usage exceeds 75%.
  - Scale in when CPU usage drops below 30%.

---

## **3. Challenges Encountered**

1. **`require_secure_transport` Configuration:**
   - The Azure API only accepts `"ON"` or `"OFF"` for this parameter. 

2. **Firewall Rules:**
   - Ensuring the correct IP ranges for VMSS instances and administrator access required careful configuration.

3. **NFS Mounting:**
   - Ensuring the NFS share was correctly mounted on all VMSS instances required testing and validation.

### **Database Connection Error**
During the deployment, the WordPress application encountered a **"Database connection error"** when trying to connect to the MySQL Flexible Server. Despite multiple troubleshooting attempts, the issue could not be fully resolved.

### **Steps Attempted to Resolve**
1. Verified the database credentials in the `wp-config.php` file:
   - Database name, username, password, and host were confirmed to match the MySQL server configuration.
2. Enabled SSL for database connections in WordPress by adding:
   ```php
   define('MYSQL_CLIENT_FLAGS', MYSQLI_CLIENT_SSL);
   ```
3. Tested the MySQL connection manually using the `mysql` CLI:
   ```bash
   mysql -h mysqlf-wordpresskrod.mysql.database.azure.com -u adminsiteswordpress -p --ssl-mode=REQUIRED
   ```
4. Adjusted the `require_secure_transport` parameter in the MySQL server configuration:
   - Temporarily set it to `OFF` to bypass SSL requirements.
5. Verified firewall rules to ensure the WordPress VM could access the MySQL server.

### **Next Steps**
Further debugging is required to identify the root cause of the connection issue. Possible areas to investigate:
- DNS resolution for the MySQL server hostname.
- Network connectivity between the WordPress VM and the MySQL server.
- Compatibility of the MySQL client used by WordPress with Azure MySQL Flexible Server.

### **Workaround**
For testing purposes, you can temporarily set `require_secure_transport` to `OFF` in the Terraform configuration:
```hcl
server_parameters = [
  {
    name  = "require_secure_transport"
    value = "OFF"
  }
]
```
Then reapply the Terraform configuration:
```bash
terraform apply
```

---

## **4. Backup and Restore**

### **Backup**
1. **WordPress Content:**
   - The NFS share is backed by Azure Storage Account containers.
   - Weekly and monthly backups are stored in separate containers (`wordpress-content-bkp-weekly` and `wordpress-content-bkp-monthly`).

2. **Database:**
   - MySQL Flexible Server backups are automatically retained for 20 days.
   - Additional manual backups can be created using:
     ```bash
     mysqldump -h mysqlf-wordpresskrod.mysql.database.azure.com -u adminsiteswordpress -p wordpress > wordpress-backup.sql
     ```

### **Restore**
1. **WordPress Content:**
   - Restore the content by copying files from the backup container to the NFS share.

2. **Database:**
   - Restore the database using:
     ```bash
     mysql -h mysqlf-wordpresskrod.mysql.database.azure.com -u adminsiteswordpress -p wordpress < wordpress-backup.sql
     ```

---

## **5. Improvements for Production**

If this was a real production site, the following improvements are recommended:

## **CI/CD and Remote Backend**

- **GitHub Actions:**
  - Set up a GitHub Actions workflow to automate the deployment process. This ensures consistent and repeatable deployments.
  - Example steps for the workflow:
    1. Validate the Terraform code.
    2. Plan the changes.
    3. Apply the changes to the infrastructure.

- **Add a Remote Backend:**
  - Use a remote backend (e.g., Azure Storage, Terraform Cloud) to store the Terraform state file securely.
  - This allows for collaboration and ensures the state file is not lost or corrupted.
  - Example configuration for Azure Storage:
    ```hcl
    terraform {
      backend "azurerm" {
        resource_group_name  = "rgp-mywplab"
        storage_account_name = "sawordpresskrod"
        container_name       = "terraform-state"
        key                  = "wordpress.tfstate"
      }
    }
    ```

### **Security Enhancements**
- **Enable HTTPS:**
  - Use Azure Application Gateway or Let's Encrypt to enable HTTPS for secure communication.
- **Web Application Firewall (WAF):**
  - Deploy a WAF to protect against common web vulnerabilities like SQL injection and XSS.
- **Secrets Management:**
  - Store sensitive information (e.g., database credentials) in Azure Key Vault.

### **Performance Enhancements**
- **Content Delivery Network (CDN):**
  - Use Azure CDN to cache and deliver static assets globally.
- **Database Scaling:**
  - Use a larger SKU for the MySQL Flexible Server to handle higher traffic.

### **Monitoring and Alerts**
- **Azure Monitor:**
  - Set up monitoring for VMSS, MySQL, and storage account metrics.
- **Alerts:**
  - Configure alerts for high CPU usage, low storage, and failed backups.

### **Disaster Recovery**
- **Geo-Redundant Backups:**
  - Enable geo-redundant backups for the MySQL Flexible Server.
- **Secondary Region:**
  - Deploy a secondary WordPress site in another Azure region for failover.

---

## **6. How to Run the Terraform Code**

1. **Pre-requisites:**
   - Install Terraform.
   - Configure Azure CLI and authenticate using:
     ```bash
     az login
     ```

2. **Run the Terraform Code:**
   - Follow the steps in the **Infrastructure Setup** section above.

3. **Clean Up:**
   - To destroy the infrastructure, run:
     ```bash
     terraform destroy
     ```

---
###

### **Set Up Local Environment Variable*
 - ** Terraform plan and Terraform apply will prompt you to insert  your Subscription ID and Password **
 - 
     ```
### **Set Up Repository Secrets if you set up GitHub Actions for Prod**
To securely store the database password, set up a repository secret:
1. Navigate to your repository on GitHub.
2. Go to **Settings** > **Secrets and variables** > **Actions**.
3. Click **New repository secret**.
4. Add a secret with the name `TF_VAR_DATABASE_MYSQL_PASSWORD` and the value of your database password.
