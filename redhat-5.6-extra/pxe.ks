# Kickstart file automatically generated by anaconda.

install
url --url http://192.168.1.2:8091/ubuntu_dvd
key --skip
lang en_US.UTF-8
keyboard us
text
# network --bootproto=dhcp
# crowbar
rootpw --iscrypted $1$H6F/NLec$Fps2Ut0zY4MjJtsa1O2yk0
firewall --disabled
authconfig --enableshadow --enablemd5
selinux --disabled
timezone --utc Europe/London
bootloader --location=mbr --driveorder=sda
zerombr yes
ignoredisk --drives=sdb,sdc,sdd,sde,sdf,sdg,sdh,sdi,sdj,sdk,sdl,sdm,sdn,sdo,sdp,sdq,sdr,sds,sdt,sdu,sdv,sdw,sdx,sdy,sdz,hdb,hdc,hdd,hde,hdf,hdg,hdh,hdi,hdj,hdk,hdl,hdm,hdn,hdo,hdp,hdq,hdr,hds,hdt,hdu,hdv,hdw,hdx,hdy,hdz
clearpart --all --drives=sda
part /boot --fstype ext3 --size=100 --ondisk=sda
part swap --recommended
part pv.6 --size=0 --grow --ondisk=sda
volgroup lv_admin --pesize=32768 pv.6
logvol / --fstype ext3 --name=lv_root --vgname=lv_admin --size=1 --grow
reboot

%packages

@base
@core
@editors
@text-internet
keyutils
trousers
fipscheck
device-mapper-multipath
OpenIPMI
OpenIPMI-tools
emacs-nox
openssh
createrepo

%post

export PS4='${BASH_SOURCE}@${LINENO}(${FUNCNAME[0]}): '
exec > /root/post-install.log 2>&1

BASEDIR="/tftpboot/redhat_dvd"
# copy the install image.
mkdir -p "$BASEDIR"
(   cd "$BASEDIR"
    while ! wget -q http://192.168.1.2:8091/files.list; do sleep 1; done
    while read f; do
	wget -a /root/post-install-wget.log -x -nH --cut-dirs=1 \
	    "http://192.168.1.2:8091/${f#./}"
    done < files.list
    rm files.list
)
cat <<EOF >/etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=none
ONBOOT=yes
NETMASK=255.255.255.0
IPADDR=192.168.124.10
GATEWAY=192.168.124.1
TYPE=Ethernet
EOF
(cd /etc/yum.repos.d && rm *)
    
cat >/etc/yum.repos.d/RHEL5.6-Base.repo <<EOF
[RHEL56-Base]
name=RHEL 5.6 Server
baseurl=file://$BASEDIR/Server
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
    
cat >/etc/yum.repos.d/crowbar-xtras.repo <<EOF
[crowbar-xtras]
name=Crowbar Extra Packages
baseurl=file://$BASEDIR/extra/pkgs
gpgcheck=0
EOF

# If we have Sun/Oracle java packages, extract their RPMs
# into our pool.

(   cd /tftpboot/redhat_dvd/extra/files/java
    for f in jdk*x64-rpm.bin; do
        [[ -f $f ]] || continue
        chmod 755 "$f"
        "./$f" -x  # just extract the RPM files.
    done
    mkdir -p /tftpboot/redhat_dvd/extra/pkgs/oracle_java
    mv *.rpm /tftpboot/redhat_dvd/extra/pkgs/oracle_java
)

# Fix links
while read file dest; do
  L_FILE=`basename $file`
  L_DIR=`dirname $file`
  T_FILE=$dest
  (cd $L_DIR ; ln -s $T_FILE $L_FILE)
done < ${BASEDIR}/crowbar_links.list

# Create the repo metadata we will need
(cd ${BASEDIR}/extra/pkgs; createrepo -d -q .)

# We prefer rsyslog.
yum -y install rsyslog
chkconfig syslog off
chkconfig rsyslog on

# Make sure rsyslog picks up our stuff
echo '$IncludeConfig /etc/rsyslog.d/*.conf' >>/etc/rsyslog.conf

# Make runlevel 3 the default
sed -i -e '/^id/ s/5/3/' /etc/inittab

mdcp() {
    local dest="$1"
    shift
    mkdir -p "$dest"
    cp "$@" "$dest"
}

finishing_scripts="update_hostname.sh parse_node_data"
(
    cd "$BASEDIR/dell"
    mdcp /opt/dell/bin $finishing_scripts
)

barclamp_scripts="barclamp_install.rb"
( 
    cd $BASEDIR/dell/barclamps/crowbar/bin
    mdcp /opt/dell/bin $barclamp_scripts
)

# Install h2n for named management
( 
    cd /opt/dell/; 
    tar -zxf ${BASEDIR}/extra/h2n.tar.gz
)
ln -s /opt/dell/h2n-2.56/h2n /opt/dell/bin/h2n    
    

# put the chef files in place
mdcp /etc/rsyslog.d "$BASEDIR/dell/rsyslog.d/"*

# Barclamp preparation (put them in the right places)
mkdir /opt/dell/barclamps
cd "$BASEDIR/dell/barclamps"
for i in *; do
  [[ -d $i ]] || continue
  if [ -e $i/crowbar.yml ]; then
    # MODULAR FORMAT copy to right location (installed by rake barclamp:install)
    cp -r $i /opt/dell/barclamps
    echo "copy new format $i"
  else
    echo "WARNING: item $i found in barclamp directory, but it is not a barclamp!"
  fi
done
cd ..
 
# Make sure the bin directory is executable
chmod +x /opt/dell/bin/*
chmod +x  ${BASEDIR}/extra/*

# Look for any crowbar specific kernel parameters
for s in $(cat /proc/cmdline); do
    VAL=${s#*=} # everything after the first =
    case ${s%%=*} in # everything before the first =
	crowbar.hostname) CHOSTNAME=$VAL;;
	crowbar.url) CURL=$VAL;;
	crowbar.use_serial_console) 
	    sed -i "s/\"use_serial_console\": .*,/\"use_serial_console\": $VAL,/" /opt/dell/chef/data_bags/crowbar/bc-template-provisioner.json;;
	crowbar.debug.logdest) 
	    echo "*.*    $VAL" >> /etc/rsyslog.d/00-crowbar-debug.conf
	    mkdir -p "$BASEDIR/rsyslog.d"
	    echo "*.*    $VAL" >> "$BASEDIR/rsyslog.d/00-crowbar-debug.conf"
	    ;;
	crowbar.authkey)
	    mkdir -p "/root/.ssh"
	    printf "$VAL\n" >>/root/.ssh/authorized_keys
	    cp /root/.ssh/authorized_keys "$BASEDIR/authorized_keys"
	    ;;
	crowbar.debug)
	    sed -i -e '/config.log_level/ s/^#//' \
		-e '/config.logger.level/ s/^#//' \
		/opt/dell/barclamps/crowbar/crowbar_framework/config/environments/production.rb
	    ;;
    esac
done
    
if [[ $CHOSTNAME ]]; then
    
    cat > /install_system.sh <<EOF
#!/bin/bash
set -e
cd ${BASEDIR}/extra
./install $CHOSTNAME

rm -f /etc/rc2.d/S99install
rm -f /etc/rc3.d/S99install
rm -f /etc/rc5.d/S99install

rm -f /install_system.sh

EOF
	
    chmod +x /install_system.sh
    ln -s /install_system.sh /etc/rc3.d/S99install
    ln -s /install_system.sh /etc/rc5.d/S99install
    ln -s /install_system.sh /etc/rc2.d/S99install
fi
