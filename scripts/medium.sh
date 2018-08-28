set -x

Uri=${1}
HANAVER=${2}
HANAUSR=${3}
HANAPWD=${4}
HANASID=${5}
HANANUMBER=${6}
vmSize=${7}
SUBEMAIL=${8}
SUBID=${9}
SUBURL=${10}

#if needed, register the machine
if [ "$SUBEMAIL" != "" ]; then
  if [ "$SUBURL" != "" ]; then 
   SUSEConnect -e $SUBEMAIL -r $SUBID --url $SUBURL
  else 
   SUSEConnect -e $SUBEMAIL -r $SUBID
  fi
fi

#install hana prereqs
zypper install -y glibc-2.22-51.6
zypper install -y systemd-228-142.1
zypper install -y unrar
zypper install -y sapconf
zypper install -y saptune
mkdir /etc/systemd/login.conf.d
mkdir /hana
mkdir /hana/data
mkdir /hana/log
mkdir /hana/shared
mkdir /hana/backup
mkdir /usr/sap

zypper in -t pattern -y sap-hana
saptune solution apply HANA
saptune daemon start

# step2
echo $Uri >> /tmp/url.txt

cp -f /etc/waagent.conf /etc/waagent.conf.orig
sedcmd="s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g"
sedcmd2="s/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=2048/g"
cat /etc/waagent.conf | sed $sedcmd | sed $sedcmd2 > /etc/waagent.conf.new
cp -f /etc/waagent.conf.new /etc/waagent.conf
#do not restart waagent, as it stops the custom script extension
#service waagent restart

number="$(lsscsi [*] 0 0 4| cut -c2)"
echo "logicalvols start" >> /tmp/parameter.txt
  datavg1lun="$(lsscsi $number 0 0 4 | grep -o '.\{9\}$')"
  datavg2lun="$(lsscsi $number 0 0 5 | grep -o '.\{9\}$')"
  logvg1lun="$(lsscsi $number 0 0 6 | grep -o '.\{9\}$')"
  logvg2lun="$(lsscsi $number 0 0 7 | grep -o '.\{9\}$')"
  pvcreate datavg $datavg1lun $datavg2lun
  vgcreate datavg $datavg1lun $datavg2lun
  lvcreate -l 1000%FREE -n datalv datavg
  pvcreate logvg $logvg1lun $logvg2lun
  vgcreate logvg $logvg1lun $logvg2lun
  lvcreate -l 100%FREE -n loglv logvg
  mkfs.xfs /dev/datavg/datalv
  mkfs.xfs /dev/logvg/loglv
echo "logicalvols end" >> /tmp/parameter.txt


#!/bin/bash
echo "logicalvols2 start" >> /tmp/parameter.txt
  sharedvglun="$(lsscsi $number 0 0 0 | grep -o '.\{9\}$')"
  usrsapvglun="$(lsscsi $number 0 0 1 | grep -o '.\{9\}$')"
  backupvglun1="$(lsscsi $number 0 0 2 | grep -o '.\{9\}$')"
  backupvglun2="$(lsscsi $number 0 0 3 | grep -o '.\{9\}$')"
  pvcreate $backupvglun1 $backupvglun2 $sharedvglun $usrsapvglun
  vgcreate backupvg $backupvglun1 $backupvglun2
  vgcreate sharedvg $sharedvglun
  vgcreate usrsapvg $usrsapvglun 
  lvcreate -l 100%FREE -n sharedlv sharedvg 
  lvcreate -l 100%FREE -n backuplv backupvg 
  lvcreate -l 100%FREE -n usrsaplv usrsapvg 
  mkfs -t xfs /dev/sharedvg/sharedlv 
  mkfs -t xfs /dev/backupvg/backuplv 
  mkfs -t xfs /dev/usrsapvg/usrsaplv
echo "logicalvols2 end" >> /tmp/parameter.txt


#!/bin/bash
echo "mounthanashared start" >> /tmp/parameter.txt
mount -t xfs /dev/sharedvg/sharedlv /hana/shared
mount -t xfs /dev/backupvg/backuplv /hana/backup 
mount -t xfs /dev/usrsapvg/usrsaplv /usr/sap
mount -t xfs /dev/datavg/datalv /hana/data
mount -t xfs /dev/logvg/loglv /hana/log 
mkdir /hana/data/sapbits
echo "mounthanashared end" >> /tmp/parameter.txt

echo "write to fstab start" >> /tmp/parameter.txt
echo "/dev/mapper/datavg-datalv /hana/data xfs defaults 0 0" >> /etc/fstab
echo "/dev/mapper/logvg-loglv /hana/log xfs defaults 0 0" >> /etc/fstab
echo "/dev/mapper/sharedvg-sharedlv /hana/shared xfs defaults 0 0" >> /etc/fstab
echo "/dev/mapper/backupvg-backuplv /hana/backup xfs defaults 0 0" >> /etc/fstab
echo "/dev/mapper/usrsapvg-usrsaplv /usr/sap xfs defaults 0 0" >> /etc/fstab
echo "write to fstab end" >> /tmp/parameter.txt

if [ ! -d "/hana/data/sapbits" ]
 then
 mkdir "/hana/data/sapbits"
fi


HANAVER=${HANAVER^^}
if [ "${HANAVER}" = "SAP HANA PLATFORM EDITION 2.0 SPS01 REV 10 (51052030)" ]
then
  hanapackage="51052030"
else
  echo "not 51052030"
  if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS02 (51052325)" ]
  then
    hanapackage="51052325"
  else
  echo "not 51052325"
    if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS03 REV30 (51053061)" ]
    then
      hanapackage="51053061"
    else
      echo "not 51053061, default to 51052325"
      hanapackage="51052325"
    fi
  fi
fi



#!/bin/bash
cd /hana/data/sapbits
echo "hana download start" >> /tmp/parameter.txt
/usr/bin/wget --quiet $Uri/SapBits/md5sums
/usr/bin/wget --quiet $Uri/SapBits/${hanapackage}_part1.exe
/usr/bin/wget --quiet $Uri/SapBits/${hanapackage}_part2.rar
/usr/bin/wget --quiet $Uri/SapBits/${hanapackage}_part3.rar
/usr/bin/wget --quiet $Uri/SapBits/${hanapackage}_part4.rar
/usr/bin/wget --quiet "https://raw.githubusercontent.com/AzureCAT-GSI/SAP-HANA-ARM/master/hdbinst.cfg"
echo "hana download end" >> /tmp/parameter.txt

date >> /tmp/testdate
cd /hana/data/sapbits

echo "hana unrar start" >> /tmp/parameter.txt
#!/bin/bash
cd /hana/data/sapbits
unrar x ${hanapackage}_part1.exe
echo "hana unrar end" >> /tmp/parameter.txt

echo "hana prepare start" >> /tmp/parameter.txt
cd /hana/data/sapbits

#!/bin/bash
cd /hana/data/sapbits
myhost=`hostname`
sedcmd="s/REPLACE-WITH-HOSTNAME/$myhost/g"
sedcmd2="s/\/hana\/shared\/sapbits\/51052325/\/hana\/data\/sapbits\/${hanapackage}/g"
sedcmd3="s/root_user=root/root_user=$HANAUSR/g"
sedcmd4="s/AweS0me@PW/$HANAPWD/g"
sedcmd5="s/sid=H10/sid=$HANASID/g"
sedcmd6="s/number=00/number=$HANANUMBER/g"
cat hdbinst.cfg | sed $sedcmd | sed $sedcmd2 | sed $sedcmd3 | sed $sedcmd4 | sed $sedcmd5 | sed $sedcmd6 > hdbinst-local.cfg
echo "hana preapre end" >> /tmp/parameter.txt

#put host entry in hosts file using instance metadata api
VMIPADDR=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text"`
VMNAME=`hostname`
cat >>/etc/hosts <<EOF
$VMIPADDR $VMNAME
EOF

#!/bin/bash
echo "install hana start" >> /tmp/parameter.txt
cd /hana/data/sapbits/${hanapackage}/DATA_UNITS/HDB_LCM_LINUX_X86_64
/hana/data/sapbits/${hanapackage}/DATA_UNITS/HDB_LCM_LINUX_X86_64/hdblcm -b --configfile /hana/data/sapbits/hdbinst-local.cfg
echo "install hana end" >> /tmp/parameter.txt
