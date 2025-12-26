# **Raspberry Pi Maintenance & Automation Suite**

A collection of Bash scripts for Raspberry Pi OS to automate system updates, application management, and Docker maintenance with automated email reporting via Gmail.  

> [!IMPORTANT]  
> This project requires `ssmtp` to be installed and configured with a Google App Password to send email reports. Standard Gmail passwords will not work due to Google's security policies.

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

To automate these scripts, add them to your root crontab:

```bash
sudo crontab -e
```

Add the following lines to run maintenance every Sunday:

```bash
# 3:00 AM - System OS Update  
0 3 * * 0 /home/pi/update_report.sh

# 4:00 AM - Python App Update  
0 4 * * 0 /home/pi/update_pi_apps.sh

# 4:20 AM - Docker Cleanup  
20 4 * * 0 /home/pi/docker_cleanup.sh

# 5:00 AM - Pi-Apps Manager Update  
0 5 * * 0 /home/pi/update_piapps_manager.sh
```

> [!NOTE]  
> Ensure you replace `/home/pi/` with the actual absolute path where you stored the scripts.

## **⚠️ Troubleshooting**

* **Permission Denied:** Ensure you are running system update scripts as root (via cron or sudo). Note that `update_piapps_manager.sh` should **not** run as root.  
* **Authorization Failed:** If you receive a "535 5.7.8" error, double-check your App Password and ensure 2-Step Verification is active on your Google account.  
* **Log Check:** Check `/var/log/syslog` for detailed SSMTP error messages.
