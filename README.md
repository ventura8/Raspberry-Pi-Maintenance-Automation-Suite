# **Raspberry Pi Maintenance & Automation Suite**

A collection of Bash scripts for Raspberry Pi OS to automate system updates, application management, and Docker maintenance with automated email reporting via Gmail.  

> [!IMPORTANT]  
> This project requires `ssmtp` to be installed and configured with a Google App Password to send email reports. Standard Gmail passwords will not work due to Google's security policies.

## **📄 Script Descriptions**

### **1\. System OS Update (`update_pi_os.sh`)**

Automates the standard Raspberry Pi OS maintenance workflow. It refreshes the package list, upgrades all installed software to the latest versions, and removes obsolete dependencies to keep the system lean and secure.

* **Commands:** `apt-get update`, `apt-get upgrade`, `apt-get autoremove`.

### **2\. Python Pip Update (`update_pip.sh`)**

Ensures your Python environment stays current. This script first upgrades the pip3 package manager itself and then identifies and upgrades all globally installed Python packages that have newer versions available.

* **Commands:** `pip3 list --outdated`, `pip3 install --upgrade --break-system-packages`.

### **3\. Pi-Apps Manager Update (`update_pi_apps.sh`)**

Specifically designed for users of the **Pi-Apps** community app store. It updates the Pi-Apps core files first and then triggers a silent, non-interactive update for every application you have installed through the Pi-Apps interface.

* **Commands:** `updater cli-yes --update-self`, `updater cli-yes --update-all`.

### **4\. Docker System Cleanup (`docker_cleanup.sh`)**

A powerful cleanup utility for Docker users. It reclaims significant disk space by removing stopped containers, unused networks, "dangling" and unused images, and all build caches.

* **Commands:** `docker system prune -a -f --volumes, docker builder prune -a -f`.

## **🚀 Features**

* **OS Updates:** Automates `apt update`, `upgrade`, and `autoremove`.  
* **App Updates:** Updates Python packages via `pip3`.  
* **Pi-Apps Integration:** Updates the Pi-Apps manager and all installed apps silently.  
* **Docker Maintenance:** Prunes unused images, containers, volumes, and build cache.  
* **Email Reports:** Sends a detailed log of every operation to your Gmail.

## **🛠️ Installation**

### **1\. Install Mail Utilities**

Run the following commands to install the necessary packages:  

```bash
sudo apt-get update  
sudo apt-get install ssmtp mailutils
```

### **2\. Configure SSMTP & Gmail**

To allow your Raspberry Pi to send emails, you must configure the `ssmtp.conf` file and set up a Google App Password.

#### **A. Generate a Google App Password**

1. Go to your [Google Account Settings](https://myaccount.google.com/).  
2. Navigate to **Security**.  
3. Ensure **2-Step Verification** is enabled (this is required).  
4. Search for or click on **App Passwords**.  
5. Select **Mail** for the app and **Other (Custom name)** for the device (e.g., "Raspberry Pi").  
6. Copy the generated **16-character code**.

#### **B. Edit the Configuration File**

Open the `ssmtp` configuration file:  

```bash
sudo nano /etc/ssmtp/ssmtp.conf
```

Use the following configuration, replacing the placeholders with your actual details:

```bash
root=your_email@gmail.com  
mailhub=smtp.gmail.com:587  
AuthUser=your_email@gmail.com  
AuthPass=your_16_character_app_password  
UseSTARTTLS=YES  
UseTLS=YES  
FromLineOverride=YES  
hostname=raspberrypi
```

#### **C. Set Secure Permissions**

Since this file contains your app password, it is critical to restrict access:  
\# Set ownership to root and the mail group  

```bash
sudo chown root:mail /etc/ssmtp/ssmtp.conf
```

\# Allow only root to read/write, and the mail group to read

```bash
sudo chmod 640 /etc/ssmtp/ssmtp.conf
```

\# Add your local user to the mail group

```bash
sudo usermod -a -G mail $(whoami)
```

> [!TIP]  
> You may need to log out and back in for the group changes to take effect.

#### **D. Test the Configuration**

Verify that the email system is working by sending a test message:

```bash
echo "Test text from Raspberry Pi" | mail -s "Test Subject" your_email@gmail.com
```

### **3\. Setup Scripts**

Clone this repo and make the scripts executable:  

```bash
chmod +x *.sh
```

## **📅 Automation (Cron Jobs)**

Automation is split between the **Root** user (for system tasks) and your **Local** user (for app-specific tasks).

### **1\. Root Crontab (`sudo crontab -e`)**

These scripts require full system privileges to manage OS packages and Docker containers.  

```bash
# 3:00 AM - System OS Update  
0 3 * * 0 /home/pi/update_pi_os.sh

# 4:00 AM - Python Pip Update (Global)
0 4 * * 0 /home/pi/update_pip.sh

# 4:20 AM - Docker Cleanup  
20 4 * * 0 /home/pi/docker_cleanup.sh
```

### **2\. User Crontab (`crontab -e`)**

This script must run as your normal user because Pi-Apps resides in your home directory. Running this as root could lead to permission conflicts.

```bash
# 5:00 AM - Pi-Apps Manager Update  
0 5 * * 0 /home/pi/update_pi_apps.sh
```

> [!NOTE]  
> Ensure you replace `/home/pi/` with the actual absolute path where you stored the scripts.

## **⚠️ Troubleshooting**

* **Permission Denied:** Ensure you are running system update scripts as root (via cron or sudo). Note that `update_pi_apps.sh` should **not** run as root.  
* **Authorization Failed:** If you receive a "535 5.7.8" error, double-check your App Password and ensure 2-Step Verification is active on your Google account.  
* **Log Check:** Check `/var/log/syslog` for detailed SSMTP error messages.
