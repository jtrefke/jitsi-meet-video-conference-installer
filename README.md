# Jitsi Meet Video Conference Installer

This project is standalone, fully automated, configurable installer for 
[Jitsi](https://jitsi.org/) from the official Debian packages. 
It provides some configuration options to quickly and 
repeatedly get your own out-of-the-box video conferencing server.

The installer will most likely work on any Debian-based system, however, it was 
only tested with Ubuntu 18.04.

It is mainly meant for disposable, temporary personal use on the Internet or 
for use in private networks as security, scalability, or optimized asset delivery 
has not been a main consideration in the implementation so far.

## Running the automated Jitsi meet installer

Get the latest release/code:
```
# Download latest release:
latest_tarball=$(curl -s https://api.github.com/repos/jtrefke/jitsi-meet-video-conference-installer/releases/latest | sed -En 's/.*tarball_url.+(http[^"]+).*/\1/p')
curl -sL "${latest_tarball}" | tar -xzf -
cd jtrefke-jitsi-meet-video-conference-installer-*

# alternatively clone the repository with git:
git clone git@github.com:jtrefke/jitsi-meet-video-conference-installer.git
cd jitsi-meet-video-conference-installer

# Create an installer configuration to be edited
cp ./jitsiinstallrc.example ./jitsiinstallrc
```

Setting up a Jitsi server with this automated installer only requires the 
following 3 steps:

1. Create a `jitsiinstallrc` file in the project root by copying the
`jitsiinstallrc.example` file
1. Adjust the configuration options as needed.
Most configuration options are optional. If no value is provided, the defaults
will be used/no changes will be made.
1. Run the installer as root or using `sudo`: `./installer/install-jitsi.sh`


## Test/develop locally using Vagrant

With `vagrant` installed, simply run `vagrant up` to create a virtual machine
that will automatically run the installer on boot.

The IP address of the virtual machine will be `10.0.3.33`; to reach the Jitsi 
server from the host system, ensure that the domain is properly mapped to that 
IP address, for instance by executing:
```
source jitsiinstallrc
echo "10.0.3.33 ${FULLY_QUALIFIED_HOSTNAME}" >> /etc/hosts
```

**Note:** When running it locally the SSL setup using letsencrypt will not work 
unless the host is reachable through the internet using the provided domain name.

## What's installed/configured?

The automated installer will setup:

- Hostname
- Firewall ports for Jitsi using `ufw`
- Jitsi using Java 8 behind nginx
- SSL certificate (using )
- Selected Jitsi configuration options

### Configuration features

**Hooks**

Hooks will load a URL via HTTP GET before Jitsi is installed as well 
as after the installation. The post-install hook will also run on reboot.
These hooks can be useful in to dynamically update DNS records in an 
unmanaged environment or when managing a dynamic machine inventory.

**SSL**

Jitsi supports letsencrypt SSL certificates out of the box, which is the 
preferred and recommended option. This option requires to provide a valid
e-mail address and to agree with the terms.
Additionally, the certificate issuance process requires a valid DNS entry and 
that the machine is reachable under the provided DNS name through the Internet 
for verification purposes. However, there are certain domains from cloud
providers for which this process will not work.
There also seem to be other constraints such as the number of certificate 
issuance requests per week, in case the server is re-installed multiple times 
withing this timeframe.

If letsencrypt is not an option, alternatively, an existing certificate and a 
key can be provided as configuration parameters.
When providing the parameter it needs to be base64 encoded and should not have 
any linebreaks; a quick way to achieve this is by running `base64 FILENAME | tr -d "\n"`.

When none of the mentioned SSL options is specified, a self-signed certificate 
will be generated.

**Authentication for meeting creation**

By default Jitsi does not require any authentication, i.e. anyone with the 
URL can create and host meetings.
Configuring the username and password will only allow users will these credentials
to start a meeting.
Once the meeting is started, anyone with the conference URL can still join 
without authenticating.

**Jitsi configurations**

A few selected features are customizable through the configuration options.
See config file for details on these options https://meet.jit.si/config.js
or compare the behavior to the reference installation at http://meet.jit.si/

**Phone dial in**

Not implemented yet.

## Sources/more info

The installer is based on some articles and resources:
- https://github.com/jitsi/jitsi-meet/blob/master/doc/quick-install.md
- https://www.reddit.com/r/linux/comments/ayy0sj/jitsimeet_authentication_for_dummies/
- https://dev.to/noandrea/self-hosted-jitsi-server-with-authentication-ie7
- https://github.com/jitsi/jitsi-meet/blob/master/resources/install-letsencrypt-cert.sh
- https://aws.amazon.com/blogs/opensource/getting-started-with-jitsi-an-open-source-web-conferencing-solution/
