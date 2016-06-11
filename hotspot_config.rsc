# Wireless - Automatically set if package is installed 
:global ssid;
:local wlanKey "MySecretKey";

# Hotspot
:local hotspotDomainName "mikrotik.local"

#------------------------------------------------------------------- 
#
# WiFi Settings
#
#-------------------------------------------------------------------
/interface wireless {
  security-profiles {
    remove [find name!=default]
    add name="private-profile" mode=dynamic-keys authentication-types=\
      wpa-psk,wpa2-psk group-ciphers=aes-ccm wpa-pre-shared-key="$wlanKey"\
      wpa2-pre-shared-key="$wlanKey"
  }
  set wlan1 mode=ap-bridge band=2ghz-b/g/n tx-chains=0,1 rx-chains=0,1 \
    disabled=no wireless-protocol=802.11 distance=indoors
  :local wlanMac  [/interface wireless get wlan1 mac-address];
  :set ssid "MikroTik-$[:pick $wlanMac 9 11]$[:pick $wlanMac 12 14]$[:pick $wlanMac 15 17]"
  set wlan1 ssid=$ssid
  set wlan1 frequency=auto;
  set wlan1 security-profile=private-profile
  set wlan1 channel-width=20/40mhz-Ce ;
  add disabled=no keepalive-frames=disabled master-interface=wlan1\
    mode=ap-bridge multicast-buffering=disabled name=wlan2\
    ssid="MikroTik-Hotspot" wds-cost-range=0 wds-default-cost=0 wps-mode=disabled\
    default-forwarding=no hide-ssid=no
}

/interface wireless reset-configuration [/interface wireless find wlan1];
/interface wireless reset-configuration [/interface wireless find wlan2];

#--------------------------------------------------------------------
#
# Hotspot
#
#--------------------------------------------------------------------
/ip address add address=192.168.182.1/24 interface=wlan2 comment="defconf: hotspot";
/ip pool add name=hotspot-pool ranges=192.168.182.10-192.168.182.254
/ip dhcp-server
  add name=hotspot address-pool="hotspot-pool" interface=wlan2 lease-time=10m disabled=no;
/ip dhcp-server network
  add address=192.168.182.0/24 gateway=192.168.182.1 comment="defconf: hotspot network";
/ip hotspot profile {
  set default dns-name="" hotspot-address=0.0.0.0 html-directory=hotspot\
    http-cookie-lifetime=3d http-proxy=0.0.0.0:0 login-by=cookie,http-chap name=default\
    rate-limit="" smtp-server=0.0.0.0 split-user-domain=no use-radius=no
  add dns-name=$hotspotDomainName hotspot-address=192.168.182.1 html-directory=hotspot\
    http-cookie-lifetime=1d http-proxy=0.0.0.0:0 login-by=cookie,http-chap name=hsprof1\
    rate-limit="" smtp-server=0.0.0.0 split-user-domain=no use-radius=no
}

/ip hotspot {
  add address-pool=hotspot-pool addresses-per-mac=2\
    disabled=no idle-timeout=5m interface=wlan2 keepalive-timeout=none\
    name=hotspot1 profile=hsprof1
  walled-garden ip add action=accept disabled=no dst-address=192.168.182.1
  user add disabled=no name=admin password=1234 profile=default
}

#--------------------------------------------------------------------
#
# Ethernet
#
#--------------------------------------------------------------------
/interface ethernet {
  set ether2 name=ether2-master;
  set ether3 master-port=ether2-master;
  set ether4 master-port=ether2-master;
  set ether5 master-port=ether2-master;
}
/interface bridge
  add name=bridge disabled=no auto-mac=yes protocol-mode=rstp comment=defconf;
:local bMACIsSet 0;
:foreach k in=[/interface find where !(slave=yes  || name~"ether1" || name~"bridge" || name~"wlan2")] do={
  :log info "k: $k"
  :local tmpPortName [/interface get $k name];
  :log info "port: $tmpPortName"
  :if ($bMACIsSet = 0) do={
    :if ([/interface get $k type] = "ether") do={
      /interface bridge set "bridge" auto-mac=no admin-mac=[/interface ethernet get $tmpPortName mac-address];
      :set bMACIsSet 1;
    }
  }
  /interface bridge port
    add bridge=bridge interface=$tmpPortName comment=defconf;
}

/ip address add address=192.168.88.1/24 interface=bridge comment="defconf";
/ip pool add name="default-dhcp" ranges=192.168.88.10-192.168.88.254;
/ip dhcp-server
  add name=defconf address-pool="default-dhcp" interface=bridge lease-time=10m disabled=no;
/ip dhcp-server network
  add address=192.168.88.0/24 gateway=192.168.88.1 comment="defconf";
/ip dns {
  set allow-remote-requests=yes
  static add name=router address=192.168.88.1
}
/ip dhcp-client add interface=ether1 disabled=no comment="defconf";

#--------------------------------------------------------------------
#
# Firewall
#
#--------------------------------------------------------------------
/ip firewall nat add chain=srcnat out-interface=ether1 action=masquerade comment="defconf: masquerade"
/ip firewall {
   filter add chain=input action=accept protocol=icmp comment="defconf: accept ICMP"
   filter add chain=input action=accept connection-state=established,related comment="defconf: accept established,related"
   filter add chain=input action=drop in-interface=ether1 comment="defconf: drop all from WAN"
   filter add chain=forward action=fasttrack-connection connection-state=established,related comment="defconf: fasttrack"
   filter add chain=forward action=accept connection-state=established,related comment="defconf: accept established,related"
   filter add chain=forward action=drop connection-state=invalid comment="defconf: drop invalid"
   fiter add action=drop chain=forward in-interface=wlan2 out-interface=!ether1 comment="defconf: hotspot"
   filter add chain=forward action=drop connection-state=new connection-nat-state=!dstnat in-interface=ether1 comment="defconf:  drop all from WAN not DSTNATed"
}
/ip firewall connection tracking set enabled=yes

/ip neighbor discovery set [find name="ether1"] discover=no
/ip neighbor discovery set [find name="wlan2"] discover=no

/tool mac-server disable [find];
/tool mac-server mac-winbox disable [find];
:foreach k in=[/interface find where !(slave=yes  || name~"ether1" || name~"wlan2")] do={
  :local tmpName [/interface get $k name];
  /tool mac-server add interface=$tmpName disabled=no;
  /tool mac-server mac-winbox add interface=$tmpName disabled=no;
}
 
:log info "Autoconfiguration ended.";
