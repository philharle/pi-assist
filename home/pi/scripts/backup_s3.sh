#!/bin/bash
# Backup data to S3

bucket="MY_BUCKET_NAME_HERE"
server="my_server_name_here"
today=`date +"%Y_%m_%d"`
overallStatus=0 #Prime the value, it's only overwritten if a failure is detected

# Create function
syncS3 () {
    now=$(date +"%Y-%m-%d %H:%M:%S")
    echo $now Syncing $1 to $bucket-$server_$today

    #As part of the sync we exclude secrets.yaml (cos we only upload an obsfucated copy), and the homeassistant DB (cos we upload a backup copy instead)
    /usr/local/bin/aws s3 cp $1 s3://$bucket/$server\_$today/$2 --recursive --exclude "*secrets.yaml" --exclude "*home-assistant_v2.db" --profile s3backup --only-show-errors

    if [ $? -eq 0 ]; then
	now=$(date +"%Y-%m-%d %H:%M:%S")
        echo $now Success
	#No need to change or overwrite overallStatus. We use the primed value above if sucessfull or the failure value if set previously
    else
        now=$(date +"%Y-%m-%d %H:%M:%S")
	echo $now Failure
        #Set overallStatus to failure
    	overallStatus=1
    fi
}

# Backup dockerconf folder
# Remember to add exclusions to function
###docker stop home-assistant > /dev/null
#Fixes issues with pi user being unable to read file
sudo chmod 644 /home/pi/dockerconf/home-assistant/nest.conf
###sudo chmod 644 /home/pi/dockerconf/jenkins/identity.key.enc
###sudo chmod 744 /home/pi/dockerconf/jenkins/secrets/
sudo chmod 644 /home/pi/dockerconf/portainer/portainer.db
sudo chmod 744 /home/pi/dockerconf/portainer/tls
sudo chmod 744 /home/pi/dockerconf/portainer/compose
#Create an copy of the secrets file with the passwords removed. We exclude the actual secrets.yaml file from uploading in the s3 copy command
tail -n +4 /home/pi/dockerconf/home-assistant/secrets.yaml | awk -F':' '{print $1 ": value_obsfucated_during_backup"}' > /home/pi/dockerconf/home-assistant/secrets.yaml_obsfucatedbackup
#Create a copy of the live DB. We'll backup this one, not the live one
cp /home/pi/dockerconf/home-assistant/home-assistant_v2.db /home/pi/dockerconf/home-assistant/home-assistant_v2.db_backup
syncS3 /home/pi/dockerconf
rm /home/pi/dockerconf/home-assistant/home-assistant_v2.db_backup
sleep 5
###docker start home-assistant > /dev/null

# Backup crontab
mkdir -p /home/pi/tmp/crontab
crontab -u pi -l >> /home/pi/tmp/crontab/crontab.tmp
syncS3 /home/pi/tmp/crontab crontab
rm -rf /home/pi/tmp/crontab

# Backup scripts
# Remember to add exclusions to function
syncS3 /home/pi/scripts scripts

# Alert on overall status
if [ $overallStatus -eq 1 ]; then
	echo "SCRIPT FAILED"
	sleep 5
	#Flash red light continuously
fi
