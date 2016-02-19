# duo-openvpn-cache
OpenVPN `auth-user-pass-verify` script with cached Duo Security 2FA.

# Installation and configuration

Follow the instructions for setting up an account and API application at https://duo.com/docs/openvpn. Instead of installing, building and configuring the Duo plugin run the following steps:

* Install nodejs and coffeescript

For Debian systems:

```
sudo apt-get install nodejs
sudo npm install -g coffee-script
```

* Clone the repo.
* Configure the server:

Your configuration should look something like:

```
auth-user-pass-verify /path/to/repository/auth.coffee via-env
setenv duo_ikey ABC123DEF456
setenv duo_skey abc123def456
setenv duo_host api-XXXXXXX.duosecurity.com
setenv duo_cachedir /path/to/fs/cache/
```

by default the script will cache credentials for 12 hours, you can adjust this by adding `setenv duo_cachehours 6` to your openvpn configuration.
