# pi-assist
Guide to setting up Home Assistant on Docker running on Raspberry Pi

The main aim of this project was to develop a basic home automation system using a Raspberry Pi, and to rely on the cloud as little as possible for the ‘hub’ aspect of the system. Whilst there is a significant dependency on cloud technology in this project (Alexa, AWS Lambda, Nest, Spotify etc.), most vendors tend to require you to use their ‘smart hubs’ which subscribe to an API hosted in the public cloud to control devices in your home, whereas I subscribe to the view that your home automation should keep functioning if there is an outage in the cloud or your internet connection goes down. The developers behind the Home Assistant software also share this belief (https://home-assistant.io/blog/2016/01/19/perfect-home-automation/#your-system-should-run-at-home-not-in-the-cloud). Also, this project exposes you to the nuts and bolts of home automation, and getting stuck in with a bit of code is always better than buying off the shelf ;)

For this project you’ll need…

* 1x Raspberry Pi (I use the Model 3 – primarily because I had one to hand, but I’d recommend it as it’s the most powerful and will have the grunt required to do things at the speed you’d expect).
* 1x USB PSU (I can’t stress enough how important it is to have a decent power supply. Don’t just expect your old cheapy 1amp mobile phone charger to be reliable).
* 1x MicroSD card (I use a Class 10 16GB one)
* 1x PiMote (I use the RT version, so that in the future I can receive data from devices in addition to sending).
* 1 or more Energenie sockets (ENER002).

Note that I’m using a fairly basic one-way Energenie system that uses 433mhz communication. This was chosen to dip my toes in the home automation world without committing a load of cash. Better systems are available that are compatible with the project below. In the future, I’m investigating adding a Z-Wave USB controller to the system to control devices using this protocol.

Also note that I’m fronting Home Assistant with an NGINX reverse proxy. This isn’t essential, however it adds an extra layer of security/caching/control etc.

### Base setup of Raspberry Pi

Download Raspbian and copy the image to the SD Card. (On a Mac I use the ‘dd’ command, however Google throws up plenty of Windows applications that allow you do write .img files to volumes too).

Create an empty file called ssh on the root of the SD Card. (This enables ssh access to the RaspberryPi by default when it starts up for the first time).

Create the file `/etc/wpa_supplicant/wpa_supplicant.conf` on the SD Card with the following content, changing the values to suit your network settings (remember that the RaspberryPi wireless chip doesn’t support 5GHz networks).
```
network={
    ssid="NAME_OF_SSID" 
    psk="WIRELESS_PASSWORD" 
}
```

Safely eject the SD Card from your computer, insert into the Raspberry Pi and power it on.

After a short while you should be able to connect using ssh to the Raspberry Pi’s IP, e.g:
```sh
$ ssh pi@192.168.0.10
```

The default password is `raspberry`

Change the hostname to the FQDN of the device
```sh
$ sudo raspi-config
```

Set the password for the ‘pi’ user to something rememberable
```sh
$ passwd
```

Add a new user (we require key authentication, so don’t set a password)
```sh
$ sudo adduser newuser1 --disabled-password
```

Switch to this user
```sh
$ su newuser1 -l
```

Add the public key for this user
```sh
$ vi ~/.ssh/authorized_keys
```

Set the permissions
```sh
$ chmod 644 ~/.ssh/authorized_keys
```

Prevent saving history (note the space before export)
```sh
$ echo " export HISTFILE=/dev/null" >> ~/.bashrc
$ exit
```

Restrict access to the pi user’s home folder
```sh
$ sudo chmod 750 /home/pi/
```

Install software updates
```sh
$ sudo apt-get update && sudo apt-get upgrade
```

Update firmware
```sh
$ sudo rpi-update
```

Disable swap file to improve longevity of SD card
```sh
$ sudo swapoff --all 
$ sudo apt-get remove dphys-swapfile
```

Install some tools
```sh
$ sudo apt-get install vim htop python3-pip
```

Include the following in global bash profile to add aliases and change colour of bash prompt
```sh
$ sudo vi /etc/bash.bashrc
```

Install some tools
```sh
$ sudo apt-get install vim htop
```

Enable key authentication and disable password authentication
```sh
$ sudo vi /etc/ssh/sshd_config
```
```
PubkeyAuthentication yes
ChallengeResponseAuthentication no
PasswordAuthentification no
UsePAM no 
```

Set static IP (or skip this step if you set up a DHCP reservation on your router)
```sh
$ sudo vi /etc/dhcpd.conf 
```
```
interface eth0 
static ip_address=x.x.x.x/y 
static routers=x.x.x.x 
static domain_name_servers=x.x.x.x
```

Create a MOTD banner
```sh
$ sudo vi /etc/motd
```

Install AWS CLI package
```sh
$ sudo pip3 install awscli --upgrade 
$ tail .bashrc -n 1 
$ export PATH="/home/pi/.local/bin/:$PATH" 
```

We’re going to programmatically update the DNS record in AWS Route53 if public IP changes. This assumes that you’ve already completed the following in AWS **_(TODO – Git Cloudformation)_**:
1.	Created a Route53 Hosted Zone
2.	Created an IAM user account with programmatic access only
3.	Created an IAM policy attached to this user with access to update the zone created in step 1
Configure AWS credentials for above user
```sh
$ aws configure --profile dnsupdate
```

Create a script to update DNS record in AWS Route53 if public IP changes
```sh
$ mkdir -p /home/pi/scripts
$ vi /home/pi/scripts/update_route53.sh
$ chmod +x /home/pi/scripts/update_route53.sh
$ (crontab -l 2>/dev/null; echo "#Update Route53"; echo "*/1 * * * * /home/pi/scripts/update_route53.shTEST >/dev/null 2>&1") | crontab –
```

Add your email address to the crontab so that you receive emails on job status
```sh
$ (crontab -l 2>/dev/null; echo "MAILTO=myemail@domain.com"; echo "") | crontab –
```

### Install Docker

Run Docker installer and allow pi user access to control it
```sh
$ sudo curl -sSL https://get.docker.com | sh 
$ sudo usermod -aG docker pi 
```

Install Docker compose
```sh
$ sudo curl -L https://github.com/mjuu/rpi-docker-compose/blob/master/v1.12.0/docker-compose-v1.12.0?raw=true -o /usr/local/bin/docker-compose && sudo chmod +x /usr/local/bin/docker-compose
```

> We need to create a new docker network for internal communication between the Home Assistant and NGINX containers. We'll publish ports 80 and 443 from NGINX to the external interface of the Raspberry Pi, however ports to Home Assistant will not be published and the only access to this container will be via connections made on the Docker ‘docker-network1’ network (in this instance from NGINX to port 8123 on Home Assistant). Also note that although NGINX is publishing port 443 externally, this can be mapped to another obfuscated external port via the port-forwarding configuration on your router.

Create new docker network
```sh
$ docker network create docker-network1
```

### Install Home Assistant

Create directory on Raspberry Pi where Home Assistant persistent config will be stored. This will be mapped through as a volume to the Docker container.
```sh
$ mkdir –p /home/pi/dockerconf/home-assistant/
```

Create a Docker container to run Home Assistant. We use the privileged switch so that the container can access the PiMote hardware which is physically plugged into the host.
```sh
$ docker run -d --restart unless-stopped --privileged --name="home-assistant" -v /home/pi/dockerconf/home-assistant:/config -v /etc/localtime:/etc/localtime:ro --network=docker-network1 lroguet/rpi-home-assistant
```
or add the following into a `docker-compose.yml` file and use `docker-compose up -d`
```yaml
homeassist1:
  container_name: home-assistant
  image: lroguet/rpi-home-assistant:latest
  net: docker-network1
  restart: unless-stopped
  privileged: true
  volumes:
    - /home/pi/dockerconf/home-assistant:/config
    - /etc/localtime:/etc/localtime:ro
```

### Install NGINX

Create directories on Raspberry Pi where NGINX persistent config, logs and SSL certificates will be stored. This will be mapped through as volumes to the Docker container.
```sh
$ mkdir –p /home/pi/dockerconf/nginx/{conf,ssl,logs}
```

Create the config for NGINX
```sh
$ vi /home/pi/dockerconf/nginx/conf/default.conf
```

Generate the DH parameters and change ownership. This uses the ‘dsaparam’ switch to speed up the generation process on the Raspberry Pi.
```sh
$ sudo openssl dhparam -dsaparam -out /home/pi/dockerconf/nginx/ssl/dhparams.pem 4096
$ sudo chown pi:pi /home/pi/dockerconf/nginx/ssl/dhparams.pem 
```

Create a Docker container to run NGINX
```sh
$ docker run -d --restart unless-stopped --name "nginx" -v /home/pi/dockerconf/nginx/conf/:/etc/nginx/sites-enabled/:ro -v /home/pi/dockerconf/nginx/ssl/:/etc/nginx/ssl/:ro -v /home/pi/dockerconf/nginx/logs/:/var/logs/nginx/:rw --network=docker-network1 -p=80:80 -p=443:443 tobi312/rpi-nginx
```
or add the following into a `docker-compose.yml` file and use `docker-compose up -d`
```yaml
nginx1:
  container_name: nginx
  image: tobi312/rpi-nginx:latest
  net: docker-network1
  restart: unless-stopped
  ports:
    - 9091:9091
  volumes:
    - /home/pi/dockerconf/nginx/conf/:/etc/nginx/sites-enabled/:ro
    - /home/pi/dockerconf/nginx/ssl/:/etc/nginx/ssl/:ro
    - /home/pi/dockerconf/nginx/logs/:/var/logs/nginx/:rw
```

### Install Let’s Encrypt

Install Let’s Encrypt binaries
```sh
$ sudo git clone https://github.com/letsencrypt/letsencrypt /opt/letsencrypt
$ sudo /opt/letsencrypt/letsencrypt-auto --debug  
```

Update Let’s Encrypt config with the chosen key size and your email address
```sh
$ sudo echo "rsa-key-size = 4096" >> /etc/letsencrypt/config.ini 
$ sudo echo "email = myemail@domain.com" >> /etc/letsencrypt/config.ini
```

> For LetsEncrypt to generate the initial certificate it will place a validation file inside a ‘.well-known’ directory on the web server. This file needs to be accessible externally on port 80. Therefore, we will stop the current NGINX container, spin up a new temporary one that serves on port 80, and connect it to the directory that LetsEncrypt will write the validation file to.

Create temporary NGINX directories
```sh 
$ mkdir –p /home/pi/dockerconf/nginx/{htmltemp,conftemp}
```

Create the temporary config for NGINX
```sh
$ vi /home/pi/dockerconf/nginx/conftemp/default.conf 
```

Create a temporary Docker container to run NGINX
```sh
$ docker run -d --name "nginx-temp" -v /home/pi/dockerconf/nginx/conftemp/:/etc/nginx/sites-enabled/:ro -v /home/pi/dockerconf/nginx/htmltemp/:/var/www/html/:ro –v -network=docker-network1 -p=80:80 -p=443:443 tobi312/rpi-nginx 
```

Ensure that you can access your FQDN externally on port 80 (HTTP) before continuing. You may need to set up a port-forwarding rule on your router if not done so already.

Ask Let’s Encrypt to generate SSL certificate, replace with your FQDN
```sh
$ /opt/letsencrypt/letsencrypt-auto certonly --webroot -w /home/pi/dockerconf/nginx/html/ -d MYFQDN.server.com --config /etc/letsencrypt/config.ini --agree-tos 
```

Once SSL certificates have been successfully created stop the temporary NGINX container and tidy up the temporary directories
```sh
$ docker stop nginx-temp 
$ docker rm nginx-temp 
$ rm -rf /home/pi/dockerconf/nginx/{htmltemp,conftemp} 
```

Create a cron job to renew SSL certificate whenever it expires, replace with your FQDN. This will check SSL expiry and create a new certificate if required, copy over the certificates to the docker volume, then finally restart NGINX.
```sh
$ (crontab -l 2>/dev/null; echo "#Renew SSL cert"; echo "0 11 * * Mon    sudo /opt/letsencrypt/letsencrypt-auto renew --config /etc/letsencrypt/config.ini --agree-tos && sudo sh -c \"echo $USER; cp /etc/letsencrypt/live/MYFQDN.server.com/*.pem /home/pi/dockerconf/nginx/ssl/; chown pi:pi /home/pi/dockerconf/nginx/ssl/*\" && docker restart nginx >/dev/null 2>&1") | crontab –
```

### S3 Backup

We’re going to backup the persistent data from the Raspberry Pi to AWS S3 every evening. This assumes that you’ve already completed the following in AWS **_(TODO – Git CloudFormation)_**:
1.	Created an S3 bucket
2.	Created an IAM user account with programmatic access only
3.	Created an IAM policy attached to this user so that they have write access into this bucket

Configure AWS credentials for above user
```sh
$ aws configure --profile s3backup
```

Create a script to run the backup to S3
```sh
$ mkdir -p /home/pi/scripts
$ vi /home/pi/scripts/backup_s3.sh
$ chmod +x /home/pi/scripts/backup_s3.sh
$ (crontab -l 2>/dev/null; echo "#Backup to S3 "; echo "30 23 * * *	/home/pi/scripts/backup_s3.sh ") | crontab –
```

Create a Lifecycle Rule on the S3 bucket to purge older backups
	Name: Purge PiDocker Backups
	Filter: prefix pidocker
	Transitions: <none>
	Expiration: 	Current & Previous versions
			Expire current version after X days
			Permanently delete previous versions after X days

### Install sSMTP

We use sSMTP to relay through to Gmail which allows us to send email from the Raspberry Pi. Install sSMTP binaries and the mailutils (providing the mail command we used to send email from scripts).
```sh
$ sudo apt-get install ssmtp mailutils
```

Edit SSMTP config. Note that if you use Google’s 2-factor authentication (if not, you should!), then you’ll need to generate an application-specific set of credentials from your Google account.
```sh
$ sudo vi /etc/ssmtp/ssmtp.conf
```

### Install AWS Logs

Install AWS Logs agent to upload log data to CloudWatch Logs
```sh
mkdir ~/temp/awslogs; cd ~/temp/awslogs
curl https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/awslogs-agent-setup.py -O
curl https://s3.amazonaws.com/aws-cloudwatch/downloads/latest/AgentDependencies.tar.gz -O
tar xvf AgentDependencies.tar.gz -C /tmp/
sudo python ./awslogs-agent-setup.py --region eu-west-1 --dependency-path /tmp/AgentDependencies
```

Specify the AWS credentials, region and log paths

The configuration file will be saved to ```/var/awslogs/etc/awslogs.conf```

You can use ```sudo service awslogs start|stop|status|restart``` to control the daemon

Diagnostic information is saved at ```/var/log/awslogs.log```

You can rerun interactive setup using ```sudo python ./awslogs-agent-setup.py --region eu-west-1 --only-generate-config```

The AWS credentials are being stored in ```/root/.aws/credentials```

Example of awslogs.conf
```
[/home/pi/dockerconf/home-assistant/scripts/pyenergenie/HA_socket_action.log]
log_stream_name = {hostname}
initial_position = start_of_file
file = /home/pi/dockerconf/home-assistant/scripts/pyenergenie/HA_socket_action.log
datetime_format = %Y-%m-%d %H:%M:%S
buffer_duration = 5000
log_group_name = /pidocker/homeassistant/energenie_socketaction

[/var/log/auth.log]
log_stream_name = {hostname}
initial_position = start_of_file
file = /var/log/auth.log
datetime_format = %Y-%m-%d %H:%M:%S
buffer_duration = 5000
log_group_name = /pidocker/auth
```

### Additional notes / Things to do

* Updating docker container images
docker-compose pull && docker-compose up
* HAASKA installation – to be documented
* Smart Devices discovery – as we’ve set the Haaska lambda ‘expose_by_default’ value to ‘false’, to enable devices in Home Assistant to show in the Alexa app you need to customise the device in Home Assistant and set the ‘haaska_hidden’ property to ‘false’.
* Script to check for Raspbian updates
* Check ssh logs
cat auth.log | grep -a -v CRON | GREP FAIL????
* Blinklight/delcom integration
* Wave-Z
* Docker container logging
NGNIX and Home-Assistant are configured to log to /dev/stdout and /dev/stderr
These are visible in Docker Logs... 
docker logs <container_name> 
However, you could also attach to the container
docker attach <container_name>
Or, execute bash 
docker exec -it <container_name> bash
* Overview of configuring Home Assistant
* Overview of integrating Home Assistant with Energenie python code
