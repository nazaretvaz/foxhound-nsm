echo "Please enter your Critical Stack API Key: "
read cs_api
echo "Please enter your SMTP server"
read cs_smtp_server
echo "Please enter your SMTP user"
read cs_smtp_user
echo "Please enter your SMTP password"
read cs_smtp_pass
echo "Please enter your notification email"
read cs_notification

echo "Check security patches"
apt-get update
apt-get -y upgrade

#NTOP PFRING LOAD BALANCING
#NO SUPPORT FOR ARM as of 03/10/2016

echo "Installing GEO-IP"
#GEOIP
wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCity.dat.gz
wget http://geolite.maxmind.com/download/geoip/database/GeoLiteCityv6-beta/GeoLiteCityv6.dat.gz
gunzip GeoLiteCity.dat.gz
gunzip GeoLiteCityv6.dat.gz
mv GeoLiteCity* /usr/share/GeoIP/
ln -s /usr/share/GeoIP/GeoLiteCity.dat /usr/share/GeoIP/GeoIPCity.dat
ln -s /usr/share/GeoIP/GeoLiteCityv6.dat /usr/share/GeoIP/GeoIPCityv6.dat

echo "Installing Required RPMs"
#PACKAGES
sudo apt-get -y install cmake make gcc g++ flex bison libpcap-dev libssl-dev python-dev swig zlib1g-dev
sudo apt-get -y install ssmtp htop vim libgeoip-dev ethtool git tshark tcpdump nmap mailutils

echo "Disabling IPv6"
#DISBALE IPV6
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
sed -i '1 s/$/ ipv6.disable=1/' /boot/cmdline.txt
sysctl -p

echo "Configuring network options"
#CONFIGURE NETWORK OPTIONS
echo "
	#!/bin/bash
	for i in rx tx gso gro; do ethtool -K eth0 $i off; done;
	ifconfig eth0 promisc
	ifconfig eth0 mtu 9000
	exit 0
	" \ >  /etc/network/if-up.d/interface-tuneup
chmod +x /etc/network/if-up.d/interface-tuneup

echo "Installing Netsniff-NG PCAP"
#PCAP - Netsniff-NG compile for ARM
mkdir /opt/pcap
touch /etc/sysconfig/netsniff-ng
touch /opt/pcap/exclude.bpf
git clone https://github.com/netsniff-ng/netsniff-ng.git
cd netsniff-ng
./configure && make && make install
echo "Creating Netsniff-NG service"
echo "[Unit]
Description=Netsniff-NG PCAP
After=network.target

[Service]
ExecStart=/usr/local/sbin/netsniff-ng --in eth0 --out /opt/pcap/ --bind-cpu 3 -s --interval 100MiB --prefix=foxhound-
Type=simple
EnvironmentFile=-/etc/sysconfig/netsniff-ng

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/netsniff-ng.service
systemctl enable netsniff-ng
systemctl daemon-reload
service netsniff-ng start

echo "Configuring SSMTP"
#SSMTP CONFIG

echo "
root=$cs_notification
mailhub=$cs_smtp_server
hostname=foxhound
FromLineOverride=YES
UseTLS=YES
UseSTARTTLS=YES
AuthUser=$cs_smtp_user
AuthPass=$cs_smtp_pass" \ > /etc/ssmtp/ssmtp.conf

#ALERT TEMPLATE
echo "#!/bin/sh
{
    echo To: $cs_notification
    echo "Mime-Version: 1.0"
	echo "Content-type: text/html; charset=”iso-8859-1”"
    echo From: bro@foxhound-ids
    echo Subject: Critical Stack Updated
    echo
    sudo -u critical-stack critical-stack-intel list
} | ssmtp $cs_notification " > /opt/email_alert.sh
chmod +x /opt/email_alert.sh


echo "Installing YARA packages"
#LOKI YARA SCANNING
apt-get -y install pip gcc python-dev python-pip autoconf libtool
echo "Installing Pylzma"
#INSTALL PYLZMA
cd /opt/
wget https://pypi.python.org/packages/fe/33/9fa773d6f2f11d95f24e590190220e23badfea3725ed71d78908fbfd4a14/pylzma-0.4.8.tar.gz
tar -zxvf pylzma-0.4.8.tar.gz
cd pylzma-0.4.8/
python ez_setup.py
python setup.py
echo "Installing YARA"
#INSTALL YARA
cd /opt/
git clone https://github.com/VirusTotal/yara.git
cd /opt/yara
./bootstrap.sh
./configure
make && make install
echo "Installing PIP LOKI Packages"
#REQUIREMENTS FOR LOKI
pip install psutil
pip install yara-python
pip install git
pip install gitpython
pip install pylzma
pip install netaddr
echo "Installing LOKI"
#INSTALL LOKI
cd /opt/
git clone https://github.com/Neo23x0/Loki.git
cd /opt/Loki
git clone https://github.com/Neo23x0/signature-base.git

#NMAP NEW HOST DISCOVERY

echo "Installing Bro"
#INSTALL BRO
sudo wget https://www.bro.org/downloads/release/bro-2.4.1.tar.gz
sudo tar -xzf bro-2.4.1.tar.gz
cd bro-2.4.1 
sudo ./configure --prefix=/usr/local/bro
sudo make -j 4
sudo make install
echo "Setting Bro variables"
#SET VARIABLES
echo "export PATH=/usr/local/bro/bin:\$PATH" >> /etc/profile

#Install Critical Stack
echo "Installing Critical Stack Agent"
sudo wget http://intel.criticalstack.com/client/critical-stack-intel-arm.deb
sudo dpkg -i critical-stack-intel-arm.deb
sudo -u critical-stack critical-stack-intel api $cs_api 
sudo rm critical-stack-intel-arm.deb
sudo -u critical-stack critical-stack-intel list
sudo -u critical-stack critical-stack-intel pull

#Deploy and start BroIDS
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/usr/local/bro/bin:\$PATH"
echo "Deploying and starting BroIDS"
sudo -i broctl check
sudo -i broctl deploy


echo "
	sudo -u critical-stack critical-stack-intel config
	echo \"#### Pulling feed update ####\"
	sudo -u critical-stack critical-stack-intel pull
	echo \"#### Applying the updates to the bro config ####\"
	broctl check
	broctl install
	echo \"#### Restarting bro ####\"
	broctl restart
" \ > /opt/criticalstack_update
sudo chmod +x /opt/criticalstack_update

#BRO REPORTING
#PYSUBNETREE
cd /opt/
git clone git://git.bro-ids.org/pysubnettree.git
cd pysubnettree/
python setup.py install
#IPSUMDUMP
cd /opt/
wget http://www.read.seas.harvard.edu/~kohler/ipsumdump/ipsumdump-1.85.tar.gz
tar -zxvf ipsumdump-1.85.tar.gz
cd ipsumdump-1.85/
./configure && make && make install

#PULL BRO SCRIPTS
mkdir /opt/bro/
mkdir /opt/bro/extracted/
cd /usr/local/bro/share/bro/site/
git clone https://github.com/sneakymonk3y/bro-scripts.git
echo "@load bro-scripts/geoip"  >> /usr/local/bro/share/bro/site/local.bro
echo "@load bro-scripts/extact"  >> /usr/local/bro/share/bro/site/local.bro

if broctl check | grep -q ' ok'; then
  broctl status
else echo "bro-script check failed"
fi

broctl deploy
broctl cron enable

#CRON JOBS
echo "0-59/5 * * * * root /usr/local/bro/bin/broctl cron" >> /etc/crontab
echo "00 7/19 * * *  root sh /opt/criticalstack_update" >> /etc/crontab
echo "0-59/5 * * * * root sh 'python loki.py -p /opt/bro/extracted/ --noprocscan --printAll --dontwait'" >> /etc/crontab 

echo "
    ______           __  __                      __
   / ____/___  _  __/ / / /___  __  ______  ____/ /
  / /_  / __ \| |/_/ /_/ / __ \/ / / / __ \/ __  / 
 / __/ / /_/ />  </ __  / /_/ / /_/ / / / / /_/ /  
/_/    \____/_/|_/_/ /_/\____/\__,_/_/ /_/\__,_/   
-  B     L     A     C     K     B     O     X  -

" \ > /etc/motd                                                                 
echo "foxhound" > /etc/hostname


